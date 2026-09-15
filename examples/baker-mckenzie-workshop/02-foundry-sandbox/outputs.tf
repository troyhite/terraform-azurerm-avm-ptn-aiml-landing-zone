# =====================================================================
# STACK B - Outputs (used to register this sandbox in Stack A)
# =====================================================================
# After this sandbox deploys, take these values into Stack A's
# `registered_sandboxes` map to wire it behind the hub AI gateway.
# =====================================================================

# Look up the Foundry (AIServices) account the module created, so we can output
# its ID/endpoint (the module itself does not expose them).
data "azurerm_resources" "foundry" {
  resource_group_name = local.resource_group_name
  type                = "Microsoft.CognitiveServices/accounts"

  depends_on = [module.ai_landing_zone]
}

locals {
  # The Foundry account name contains "ai-foundry"; Content Safety (if any) does not.
  foundry_accounts = [for r in data.azurerm_resources.foundry.resources : r if strcontains(r.name, "foundry")]
  foundry_name     = try(local.foundry_accounts[0].name, null)
}

output "resource_group_name" {
  description = "The sandbox resource group."
  value       = local.resource_group_name
}

output "team_name" {
  description = "Team key - use this as the map key when registering in Stack A."
  value       = var.team_name
}

output "foundry_account_name" {
  description = "Foundry account name (null if the lookup could not resolve it - see foundry_lookup_command)."
  value       = local.foundry_name
}

output "foundry_openai_endpoint" {
  description = "Foundry OpenAI endpoint to register as the APIM backend in Stack A."
  value       = local.foundry_name != null ? "https://${local.foundry_name}.openai.azure.com/" : null
}

output "foundry_resource_id" {
  description = "Foundry account resource ID (for RBAC / backend config in Stack A)."
  value       = try(local.foundry_accounts[0].id, null)
}

output "sandbox_vnet_id" {
  description = "Sandbox VNet resource ID (peered to the hub)."
  value       = try(module.ai_landing_zone.virtual_network.resource_id, null)
}

output "foundry_lookup_command" {
  description = "Fallback: run this to fetch the Foundry endpoint if the output above is null."
  value       = "az cognitiveservices account show -g ${local.resource_group_name} -n <foundry-account-name> --query properties.endpoint -o tsv"
}

output "register_in_stack_a" {
  description = "Copy/paste block for Stack A terraform.tfvars registered_sandboxes map."
  value       = <<-EOT
    "${var.team_name}" = {
      display_name         = "${var.team_name} / ${var.use_case}"
      foundry_openai_url   = "${local.foundry_name != null ? "https://${local.foundry_name}.openai.azure.com/" : "<run foundry_lookup_command>"}"
      foundry_resource_id  = "${try(local.foundry_accounts[0].id, "<run foundry_lookup_command>")}"
      monthly_token_limit  = 200000
    }
  EOT
}
