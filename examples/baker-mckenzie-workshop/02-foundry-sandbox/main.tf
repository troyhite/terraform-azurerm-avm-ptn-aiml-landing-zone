terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.21"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  storage_use_azuread = true
  # Focused RP set; pre-register out of band (see README). Broad auto-registration
  # can time out on unrelated providers.
  resource_provider_registrations = "none"
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    cognitive_account {
      # Purge Foundry/Cognitive accounts on destroy so repeat demo runs don't
      # collide with soft-deleted names.
      purge_soft_delete_on_destroy = true
    }
  }
}

data "azurerm_client_config" "current" {}

module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.2"
}

# =====================================================================
# STACK B - Governed Foundry sandbox (per team / per subscription)
# =====================================================================
# Posture A' (private mesh): Foundry is private (module hardcodes private
# endpoints). The hub AI Gateway (Stack A) reaches it over a private path, so
# this sandbox peers to the hub VNet and links its private DNS zones to the hub.
# Clients never touch this directly - they go through the hub gateway URL.
# =====================================================================

locals {
  # name_prefix must be short: the Foundry storage naming pattern appends
  # "<key>fndrysa<token>" (~16 chars) and the account name cap is 24, so keep the
  # prefix <= 7. Strip hyphens and truncate the team name.
  name_prefix = substr(replace(var.team_name, "-", ""), 0, 7)

  # Showback + governance tags applied to every resource. Derrick's cost view is
  # a filter on these. The ethical-wall / residency story lives here too.
  tags = {
    team                  = var.team_name
    "use-case"            = var.use_case
    matter                = var.matter_id
    environment           = var.environment
    "data-classification" = var.data_classification
    "cost-center"         = var.cost_center
    owner                 = var.owner_email
    workload              = "ai-foundry-sandbox"
    "managed-by"          = "terraform"
  }

  # Model catalog: maps an allowed model name to its deployment details. Embedding
  # models are pinned to Standard (broadest availability); chat models use the
  # requested deployment type (DataZoneStandard by default for data residency).
  model_catalog = {
    "gpt-4.1"                = { format = "OpenAI", version = "2025-04-14", scale_type = var.model_deployment_type }
    "gpt-4o"                 = { format = "OpenAI", version = "2024-11-20", scale_type = var.model_deployment_type }
    # Embedding models often lack Standard/DataZone SKUs in a given region (e.g.
    # text-embedding-3-large has no Standard SKU in centralus), so pin them to
    # GlobalStandard for broad availability. Note: embeddings are then processed
    # globally - acceptable for most RAG, but call it out if strict residency is
    # required for the embedded text.
    "text-embedding-3-large" = { format = "OpenAI", version = "1", scale_type = "GlobalStandard" }
    "text-embedding-3-small" = { format = "OpenAI", version = "1", scale_type = "GlobalStandard" }
  }

  # Render the allow-list into actual Foundry model deployments.
  ai_model_deployments = {
    for m in var.allowed_models : m => {
      name = m
      model = {
        format  = local.model_catalog[m].format
        name    = m
        version = local.model_catalog[m].version
      }
      scale = {
        type     = local.model_catalog[m].scale_type
        capacity = 1
      }
    }
  }

  # The first project. Cosmos connection is added only when Cosmos is enabled.
  ai_projects = {
    project_1 = merge(
      {
        name                       = "${var.team_name}-project"
        description                = "Governed sandbox project for ${var.team_name} - ${var.use_case}"
        display_name               = "${var.team_name} / ${var.use_case}"
        create_project_connections = true
        ai_search_connection       = { new_resource_map_key = "this" }
        storage_account_connection = { new_resource_map_key = "this" }
      },
      var.enable_cosmos ? { cosmos_db_connection = { new_resource_map_key = "this" } } : {}
    )
  }

  # Sandbox vs production posture (light toggle - the promotion story).
  is_production = var.environment == "production"

  # Computed once so the module, the policy scope, and outputs all agree.
  resource_group_name = coalesce(var.resource_group_name, "rg-ailz-${local.name_prefix}-${substr(module.naming.unique-seed, 0, 5)}")
  resource_group_id   = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.resource_group_name}"

  # Distinct model publishers for the governed-catalog Azure Policy.
  allowed_model_publishers = distinct([for m in var.allowed_models : local.model_catalog[m].format])
}

module "ai_landing_zone" {
  source = "../../../"

  location            = var.location
  resource_group_name = local.resource_group_name
  name_prefix         = local.name_prefix
  enable_telemetry    = var.enable_telemetry
  tags                = local.tags

  # Self-contained sandbox that owns its DNS/routing (the hub is a homelab VNet,
  # not a full platform landing zone). Direct internet egress (no spoke firewall).
  flag_platform_landing_zone = false
  use_internet_routing       = true

  # Peer to the hub VNet so the hub APIM can route to the Foundry private endpoint.
  vnet_definition = {
    name          = "vnet-ailz-${local.name_prefix}"
    address_space = var.spoke_vnet_address_space
    vnet_peering_configuration = {
      peer_vnet_resource_id   = var.hub_vnet_resource_id
      allow_forwarded_traffic = true
      allow_gateway_transit   = false
      create_reverse_peering  = var.create_reverse_hub_peering
      use_remote_gateways     = false
    }
  }

  # NOTE: the sandbox VNet still PEERS to the hub (above) for network reachability.
  # We intentionally do NOT link this sandbox's private DNS zones to the hub VNet:
  # a hub VNet can link to only one zone per namespace, and another sandbox on the
  # same homelab hub already linked its privatelink.* zones there. The sandbox's own
  # zones are linked to its own VNet automatically, so it is fully self-resolving.
  # Hub-side resolution for the AI gateway is handled separately in Stack A (it is
  # not solvable by naive per-sandbox hub links when multiple sandboxes share a hub).
  private_dns_zones = {}

  # No gateway/firewall/bastion/VMs in the sandbox. The gateway lives in the hub
  # (Stack A). VMs are off because governed subscriptions force Key Vault private,
  # which blocks the module VMs' admin-password write (see README).
  apim_definition = {
    deploy          = false
    publisher_email = var.owner_email
    publisher_name  = var.team_name
  }
  firewall_definition = { deploy = false }
  bastion_definition  = { deploy = false }
  buildvm_definition  = { deploy = false }
  jumpvm_definition   = { deploy = false }

  # Container Apps hosting tier is not needed for the Foundry + gateway demo, and
  # its AKS-backed environment hit capacity limits in Central US. Disable it -
  # nothing in this module depends on it (main.genai_app_resources.tf is empty).
  container_app_environment_definition = { deploy = false }
  app_gateway_definition = {
    deploy                = false
    backend_address_pools = {}
    backend_http_settings = {}
    frontend_ports        = {}
    http_listeners        = {}
    request_routing_rules = {}
  }

  # GenAI Key Vault stays fully private (correct posture; enforced by policy in
  # governed subscriptions regardless).
  genai_key_vault_definition = {
    public_network_access_enabled = false
    network_acls = {
      bypass         = "AzureServices"
      default_action = "Deny"
      ip_rules       = []
    }
  }

  # Foundry account, the allow-listed model deployments, and the first project.
  ai_foundry_definition = {
    purge_on_destroy = true
    ai_foundry = {
      create_ai_agent_service = true
      # Entra-only auth (no keys). Developers and the hub APIM authenticate with
      # their own / managed identities - the secure self-service story.
      disable_local_auth = true
      # Grant the team's developer group least-privilege access to build in THIS
      # sandbox only (ethical wall between teams). Empty when no group is supplied.
      role_assignments = var.developer_group_object_id == null ? {} : {
        developers = {
          role_definition_id_or_name = "Azure AI Developer"
          principal_id               = var.developer_group_object_id
          principal_type             = "Group"
        }
      }
    }
    ai_model_deployments = local.ai_model_deployments
    ai_projects          = local.ai_projects

    ai_search_definition = {
      this = {}
    }

    # Cosmos is wired but OFF by default (empty map = not deployed) to keep the
    # demo lean. Set enable_cosmos = true to include agent-state storage.
    cosmosdb_definition = var.enable_cosmos ? { this = { consistency_level = "Session" } } : {}

    key_vault_definition = {
      this = {}
    }

    storage_account_definition = {
      this = {
        endpoints = {
          blob = {
            type = "blob"
          }
        }
      }
    }
  }
}
