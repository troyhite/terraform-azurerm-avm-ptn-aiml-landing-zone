terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.21"
    }
  }
}

provider "azurerm" {
  resource_provider_registrations = "none"
  features {}
}

data "azurerm_client_config" "current" {}

# =====================================================================
# STACK A - Hub AI Gateway (Azure API Management)
# =====================================================================
# One public front door for every Foundry sandbox. Clients call the gateway URL
# with their team's subscription key + Entra auth; APIM authenticates onward to
# each private Foundry with its managed identity, enforces per-team token limits,
# and emits per-team token metrics for showback.
# =====================================================================

locals {
  # Parse the hub VNet resource ID into its parts so we can add an APIM subnet.
  hub_vnet_parts = split("/", var.hub_vnet_resource_id)
  hub_vnet_rg    = local.hub_vnet_parts[4]
  hub_vnet_name  = local.hub_vnet_parts[8]

  # v2 tiers (BasicV2/StandardV2/PremiumV2) use outbound VNet integration, which
  # REQUIRES the subnet be delegated to Microsoft.Web/serverFarms and does NOT need
  # the classic control-plane NSG. Classic tiers (Developer/Premium) use External/
  # Internal injection: NO delegation, but an NSG allowing inbound 3443 is required.
  apim_is_v2 = length(regexall("V2_", var.apim_sku)) > 0
}

resource "azurerm_resource_group" "hub" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    workload   = "ai-gateway-hub"
    managed-by = "terraform"
  }
}

# APIM integration subnet, created inside the EXISTING hub VNet.
resource "azurerm_subnet" "apim" {
  name                 = "snet-apim-gateway"
  resource_group_name  = local.hub_vnet_rg
  virtual_network_name = local.hub_vnet_name
  address_prefixes     = [var.apim_subnet_address_prefix]

  # Only for v2 VNet integration. Removed automatically if you fall back to a
  # classic SKU (Developer_1), which must not carry this delegation.
  dynamic "delegation" {
    for_each = local.apim_is_v2 ? [1] : []
    content {
      name = "apim-v2-vnet-integration"
      service_delegation {
        name    = "Microsoft.Web/serverFarms"
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }
}

# NSG on the integration subnet. REQUIRED for every VNet mode - classic External/
# Internal injection needs inbound 3443/6390, and StandardV2 outbound integration
# also requires an NSG to be associated (even though its rules can be permissive).
resource "azurerm_network_security_group" "apim" {
  name                = "nsg-apim-gateway"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name

  security_rule {
    name                       = "APIM-Management-3443"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3443"
    source_address_prefix      = "ApiManagement"
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "AzureLoadBalancer-6390"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6390"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "VirtualNetwork"
  }

  tags = {
    workload   = "ai-gateway-hub"
    managed-by = "terraform"
  }
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  subnet_id                 = azurerm_subnet.apim.id
  network_security_group_id = azurerm_network_security_group.apim.id
}

# The gateway. System-assigned identity is used to authenticate to each Foundry.
resource "azurerm_api_management" "gateway" {
  name                 = var.apim_name
  location             = var.location
  resource_group_name  = azurerm_resource_group.hub.name
  publisher_name       = var.publisher_name
  publisher_email      = var.publisher_email
  sku_name             = var.apim_sku
  virtual_network_type = "External"

  # The subnet must have its NSG associated BEFORE APIM deploys into it, otherwise
  # Azure rejects the create with NetworkSecurityGroupNotFound (the association is
  # not an implicit dependency of the subnet reference below).
  depends_on = [azurerm_subnet_network_security_group_association.apim]

  virtual_network_configuration {
    subnet_id = azurerm_subnet.apim.id
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    workload   = "ai-gateway-hub"
    managed-by = "terraform"
  }
}

# --- Per-sandbox wiring (one set of resources per registered team) ---

# Backend → the team's private Foundry OpenAI endpoint.
resource "azurerm_api_management_backend" "foundry" {
  for_each = var.registered_sandboxes

  name                = "foundry-${each.key}"
  resource_group_name = azurerm_resource_group.hub.name
  api_management_name = azurerm_api_management.gateway.name
  protocol            = "http"
  url                 = "${trimsuffix(each.value.foundry_openai_url, "/")}/openai"
}

# One API per team (path = team name). Keeps teams cleanly separated at the gateway.
resource "azurerm_api_management_api" "aoai" {
  for_each = var.registered_sandboxes

  name                  = "aoai-${each.key}"
  resource_group_name   = azurerm_resource_group.hub.name
  api_management_name   = azurerm_api_management.gateway.name
  revision              = "1"
  display_name          = "Azure OpenAI - ${each.value.display_name}"
  path                  = each.key
  protocols             = ["https"]
  subscription_required = true

  # Minimal spec: proxy Azure OpenAI's inference paths. Import a full OpenAPI in
  # production; for the demo this passes chat/completions/embeddings through.
  import {
    content_format = "openapi+json"
    content_value = jsonencode({
      openapi = "3.0.1"
      info    = { title = "Azure OpenAI - ${each.key}", version = "1.0" }
      paths = {
        "/deployments/{deployment-id}/chat/completions" = {
          post = {
            operationId = "chat-completions"
            parameters = [{
              name = "deployment-id", in = "path", required = true, schema = { type = "string" }
            }]
            responses = { "200" = { description = "OK" } }
          }
        }
        "/deployments/{deployment-id}/embeddings" = {
          post = {
            operationId = "embeddings"
            parameters = [{
              name = "deployment-id", in = "path", required = true, schema = { type = "string" }
            }]
            responses = { "200" = { description = "OK" } }
          }
        }
      }
    })
  }
}

# The AI-gateway governance policy (the heart of the demo):
#  - authentication-managed-identity : APIM's MI authenticates to private Foundry
#  - set-backend-service             : route to this team's Foundry backend
#  - azure-openai-token-limit        : per-team fair-use ceiling
#  - azure-openai-emit-token-metric  : per-team token metrics -> showback
resource "azurerm_api_management_api_policy" "governance" {
  for_each = var.registered_sandboxes

  api_name            = azurerm_api_management_api.aoai[each.key].name
  api_management_name = azurerm_api_management.gateway.name
  resource_group_name = azurerm_resource_group.hub.name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
    <set-backend-service backend-id="${azurerm_api_management_backend.foundry[each.key].name}" />
    <azure-openai-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="${max(1000, floor(each.value.monthly_token_limit / 43200))}" estimate-prompt-tokens="true" remaining-tokens-variable-name="remainingTokens" />
    <azure-openai-emit-token-metric namespace="ai-gateway">
      <dimension name="team" value="${each.key}" />
      <dimension name="api" value="${each.value.display_name}" />
    </azure-openai-emit-token-metric>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
XML
}

# Product per team (carries the subscription/access boundary).
resource "azurerm_api_management_product" "team" {
  for_each = var.registered_sandboxes

  product_id            = "team-${each.key}"
  resource_group_name   = azurerm_resource_group.hub.name
  api_management_name   = azurerm_api_management.gateway.name
  display_name          = "AI Access - ${each.value.display_name}"
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "team" {
  for_each = var.registered_sandboxes

  product_id          = azurerm_api_management_product.team[each.key].product_id
  api_name            = azurerm_api_management_api.aoai[each.key].name
  api_management_name = azurerm_api_management.gateway.name
  resource_group_name = azurerm_resource_group.hub.name
}

# The team's subscription key (what their apps present at the gateway).
resource "azurerm_api_management_subscription" "team" {
  for_each = var.registered_sandboxes

  resource_group_name = azurerm_resource_group.hub.name
  api_management_name = azurerm_api_management.gateway.name
  product_id          = azurerm_api_management_product.team[each.key].id
  display_name        = "Key - ${each.value.display_name}"
  state               = "active"
}

# Let the gateway's managed identity call each team's Foundry (Entra auth, no keys).
resource "azurerm_role_assignment" "apim_to_foundry" {
  for_each = var.registered_sandboxes

  scope                = each.value.foundry_resource_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.gateway.identity[0].principal_id
}

# Send gateway telemetry (incl. token metrics) to the hub Log Analytics workspace.
resource "azurerm_monitor_diagnostic_setting" "apim" {
  name                       = "to-hub-law"
  target_resource_id         = azurerm_api_management.gateway.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "GatewayLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}
