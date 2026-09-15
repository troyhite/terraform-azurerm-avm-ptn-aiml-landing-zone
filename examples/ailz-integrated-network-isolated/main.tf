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
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  storage_use_azuread = true
  # The module only needs a focused set of resource providers. Disable the
  # provider's broad auto-registration (which timed out on unrelated RPs like
  # Microsoft.AppPlatform) and pre-register the required RPs out of band.
  resource_provider_registrations = "none"
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      delete_os_disk_on_deletion = true
    }
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}

data "azurerm_client_config" "current" {}

# Unique, CAF-compliant fallback names.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.2"
}

# =====================================================================
# AI Landing Zone - hub-peered spoke, network isolation ON
#
# Adjusted from strict Bicep ailz-integrated because the target hub is a
# homelab VNet, not a full platform landing zone that already hosts the
# privatelink.* Private DNS zones. This spoke still peers to the hub and reuses
# the hub Log Analytics workspace, but the module OWNS its Private DNS zones and
# routing (flag_platform_landing_zone = false).
#
#   Network isolation (NETWORK_ISOLATION=true)   -> module defaults: private endpoints,
#                                                   public access disabled on PaaS planes
#   Peer to existing hub                          -> vnet_definition.vnet_peering_configuration
#   Reuse hub Log Analytics workspace             -> law_definition.resource_id
#   Module-owned Private DNS zones                -> flag_platform_landing_zone = false
#   Direct internet egress (no spoke firewall)    -> use_internet_routing = true
#   Reuse hub Bastion, own jumpbox                -> bastion_definition.deploy = false, jumpvm deploy = true
#
# To run true ailz-integrated (flag = true) instead, first create all
# privatelink.* zones in the hub (or enable Azure Policy DINE), then set
# flag_platform_landing_zone = true and point private_dns_zones at the hub RG.
# =====================================================================

module "ai_landing_zone" {
  source = "../../"

  location            = var.location
  resource_group_name = coalesce(var.resource_group_name, "ai-lz-rg-ailz-${substr(module.naming.unique-seed, 0, 5)}")
  name_prefix         = var.name_prefix
  enable_telemetry    = var.enable_telemetry

  # NOTE ON TOPOLOGY (adjusted for a homelab-style hub):
  # This deploys a self-contained spoke that STILL peers to the existing hub, but
  # the AI landing zone creates and manages its own Private DNS zones and routing.
  # flag_platform_landing_zone = true assumes the hub already hosts all ~14
  # privatelink.* zones (a full platform landing zone). A homelab hub does not, so
  # we use false here and let the module own DNS. Network isolation is unchanged.
  flag_platform_landing_zone = false

  # No spoke Azure Firewall in this demo; route spoke egress straight to the
  # internet (valid only when flag_platform_landing_zone = false).
  use_internet_routing = true

  # Spoke VNet created by the module and peered to the existing hub. DNS is left
  # as Azure-provided so the module-managed Private DNS zones resolve correctly
  # (do not set custom hub DNS servers here, or private endpoint names won't resolve).
  vnet_definition = {
    name          = var.spoke_vnet_name
    address_space = var.spoke_vnet_address_space
    vnet_peering_configuration = {
      peer_vnet_resource_id   = var.hub_vnet_resource_id
      allow_forwarded_traffic = true
      allow_gateway_transit   = false
      create_reverse_peering  = var.create_reverse_hub_peering
      use_remote_gateways     = false
    }
  }

  # Module creates and links its own Private DNS zones (flag_platform_landing_zone
  # = false). No existing hub zones are referenced.

  # Reuse the hub Log Analytics workspace instead of creating a spoke workspace.
  law_definition = {
    resource_id = var.hub_log_analytics_workspace_resource_id
  }

  # Reuse hub Bastion (reachable over the peering); do not deploy one in the spoke.
  bastion_definition = {
    deploy = false
  }

  # Hub already provides Azure Firewall; do not deploy a spoke firewall.
  firewall_definition = {
    deploy = false
  }

  # Public ingress via Application Gateway is off for this internal demo.
  # (The object's collection attributes are required by the type even when
  # deploy = false, so they're passed as empty maps. Flip deploy = true and
  # populate these to expose a public entry point.)
  app_gateway_definition = {
    deploy                = false
    backend_address_pools = {}
    backend_http_settings = {}
    frontend_ports        = {}
    http_listeners        = {}
    request_routing_rules = {}
  }

  # Both management VMs are OFF. This subscription inherits a management-group
  # Azure Policy that FORCES Key Vault to private-only (public network access
  # cannot be enabled - even `az keyvault update` is refused). The AVM jump/build
  # VMs write their admin password into the GenAI Key Vault from the deployer's
  # public IP during creation, which that policy blocks (403 ForbiddenByConnection).
  # So neither VM can be provisioned from outside the VNet here. The private KV is
  # the correct Zero Trust end state; manage the environment via the control plane
  # (Portal / az / Cloud Shell) - see README. To run a jumpbox in a subscription
  # WITHOUT that policy, set jumpvm deploy = true and deployer_ip_address.
  buildvm_definition = {
    deploy = false
  }
  jumpvm_definition = {
    deploy = false
  }

  # API Management integrated into the spoke VNet (Internal). Public network
  # access must be enabled at creation time for an Internal-VNet APIM - Azure
  # rejects creating it with public access disabled - but the gateway is still
  # only reachable inside the VNet.
  apim_definition = {
    deploy                        = true
    deploy_sample_apis            = true
    publisher_email               = var.apim_publisher_email
    publisher_name                = var.apim_publisher_name
    virtual_network_type          = "Internal"
    public_network_access_enabled = true
  }

  # GenAI Key Vault stays fully private. A management-group policy on this
  # subscription enforces this regardless, and it is the correct posture. No
  # public IP exception is set (it could not be honored anyway).
  genai_key_vault_definition = {
    public_network_access_enabled = false
    network_acls = {
      bypass         = "AzureServices"
      default_action = "Deny"
      ip_rules       = []
    }
  }

  # AI Foundry account, an approved model deployment, and a first project.
  ai_foundry_definition = {
    purge_on_destroy = true
    ai_foundry = {
      create_ai_agent_service = true
    }
    ai_model_deployments = {
      "gpt-4.1" = {
        name = "gpt-4.1"
        model = {
          format  = "OpenAI"
          name    = "gpt-4.1"
          version = "2025-04-14"
        }
        scale = {
          type     = "GlobalStandard"
          capacity = 1
        }
      }
    }
    ai_projects = {
      project_1 = {
        name                       = "project-1"
        description                = "First governed use-case project"
        display_name               = "Project 1"
        create_project_connections = true
        cosmos_db_connection = {
          new_resource_map_key = "this"
        }
        ai_search_connection = {
          new_resource_map_key = "this"
        }
        storage_account_connection = {
          new_resource_map_key = "this"
        }
      }
    }
    ai_search_definition = {
      this = {}
    }
    cosmosdb_definition = {
      this = {
        consistency_level = "Session"
      }
    }
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
