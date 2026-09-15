# =====================================================================
# STACK A - Hub AI Gateway : inputs
# =====================================================================
# Deployed ONCE into the hub / platform subscription. Fronts every Foundry
# sandbox (Stack B) behind a single Azure API Management gateway. Registering a
# new team = adding an entry to registered_sandboxes and re-applying (minutes).
# =====================================================================

variable "location" {
  type        = string
  default     = "centralus"
  description = "Region for the hub gateway. Keep it close to the sandboxes."
}

variable "resource_group_name" {
  type        = string
  default     = "rg-ai-gateway-hub"
  description = "Resource group for the hub gateway. Created by this stack."
}

variable "apim_name" {
  type        = string
  default     = "apim-ai-gateway-hub"
  description = "Globally-unique APIM name."
}

variable "apim_sku" {
  type        = string
  default     = "StandardV2_1"
  description = <<DESCRIPTION
APIM SKU. StandardV2_1 (chosen): fast to provision, VNet integration for outbound
calls to private Foundry. If v2 VNet integration errors at apply on your provider
version, switch to "Developer_1" for classic External VNet injection (well-
supported in Terraform, but ~30-40 min to provision and no SLA).
DESCRIPTION
}

variable "publisher_name" {
  type        = string
  default     = "Baker McKenzie AI Platform"
  description = "APIM publisher name."
}

variable "publisher_email" {
  type        = string
  default     = "aiplatform@bakermckenzie.com"
  description = "APIM publisher email."
}

variable "hub_vnet_resource_id" {
  type        = string
  description = "Existing hub VNet the gateway integrates into (same VNet the sandboxes peer to)."
}

variable "apim_subnet_address_prefix" {
  type        = string
  default     = "10.0.250.0/27"
  description = "Address prefix for the APIM integration subnet created in the hub VNet. Must be inside the hub VNet's space and unused."
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Hub Log Analytics workspace resource ID. Per-team token metrics land here for showback."
}

variable "registered_sandboxes" {
  type = map(object({
    display_name        = string
    foundry_openai_url  = string
    foundry_resource_id = string
    monthly_token_limit = optional(number, 200000)
  }))
  default     = {}
  description = <<DESCRIPTION
The sandboxes fronted by this gateway. The map KEY is the team name (from Stack B's
output). Each entry needs the team's Foundry OpenAI endpoint and resource ID (from
Stack B outputs). Start empty, add one entry after the first sandbox deploys, then
re-apply. Each entry produces: an APIM backend, API, product, subscription key, and
token-governance policy for that team.
DESCRIPTION
}
