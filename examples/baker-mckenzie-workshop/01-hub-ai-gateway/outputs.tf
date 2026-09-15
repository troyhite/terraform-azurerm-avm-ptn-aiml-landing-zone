# =====================================================================
# STACK A - Outputs
# =====================================================================

output "gateway_url" {
  description = "The single public front door. Clients call this + their team key."
  value       = azurerm_api_management.gateway.gateway_url
}

output "gateway_principal_id" {
  description = "APIM managed identity object ID (granted Cognitive Services OpenAI User on each Foundry)."
  value       = azurerm_api_management.gateway.identity[0].principal_id
}

output "registered_teams" {
  description = "Teams currently fronted by the gateway."
  value       = keys(var.registered_sandboxes)
}

output "team_subscription_key_command" {
  description = "How to read each team's subscription (primary) key - keys are sensitive and not exported directly."
  value = {
    for k, v in var.registered_sandboxes : k =>
    "az apim api subscription show ... # or Portal: APIM > Subscriptions > Key - ${v.display_name}"
  }
}

output "example_call" {
  description = "Shape of a client call through the gateway (per team)."
  value = {
    for k, v in var.registered_sandboxes : k =>
    "POST ${azurerm_api_management.gateway.gateway_url}/${k}/deployments/gpt-4.1/chat/completions?api-version=2024-10-21  (header: api-key: <team-subscription-key>)"
  }
}
