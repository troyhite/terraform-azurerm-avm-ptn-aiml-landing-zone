variable "enable_telemetry" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see <https://aka.ms/avm/telemetryinfo>.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
}

variable "location" {
  type        = string
  default     = "eastus2"
  description = "Azure region for the AI landing zone (spoke). Keep this in the same region as the hub so the reused hub Bastion works (Bastion peering is regional)."
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "Name of the resource group the module creates for the spoke. If null, a name is generated. The RG must not already exist."
}

variable "name_prefix" {
  type        = string
  default     = "bakerailz"
  description = "Prefix applied to generated resource names. Lowercase alphanumeric, 10 characters or fewer."
}

variable "spoke_vnet_name" {
  type        = string
  default     = "vnet-ailz-spoke"
  description = "Name for the spoke virtual network the module creates."
}

variable "spoke_vnet_address_space" {
  type        = list(string)
  default     = ["192.168.0.0/23"]
  description = "Address space for the spoke VNet. Must not overlap the hub or any peered network."
}

# --- Hub integration (mirrors the Bicep ailz-integrated hub reuse) ---

variable "hub_vnet_resource_id" {
  type        = string
  description = "Resource ID of the EXISTING hub VNet to peer the spoke to. Mirrors Bicep HUB_INTEGRATION_HUB_VNET_RESOURCE_ID."
}

variable "hub_dns_servers" {
  type        = list(string)
  description = "Custom DNS server IPs the spoke should use (e.g. the hub Azure Private DNS Resolver inbound endpoint IPs, or the hub Azure Firewall DNS proxy IP). Required so private endpoint names resolve through the hub."
}

variable "hub_private_dns_zones_rg_resource_id" {
  type        = string
  description = "Resource ID of the resource group that holds the hub's existing Private DNS zones (privatelink.*). Mirrors the Bicep existingPrivateDnsZone* / policyManagedPrivateDns reuse."
}

variable "hub_log_analytics_workspace_resource_id" {
  type        = string
  description = "Resource ID of the hub Log Analytics workspace to reuse for diagnostics. Mirrors Bicep EXISTING_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID."
}

variable "create_reverse_hub_peering" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
Whether Terraform also creates the reverse hub -> spoke peering.

Set to true only when the deployer identity has write access to the hub VNet's resource group. If the hub is managed by a separate platform team (common), set this to false and have the platform team create the reverse peering, matching the Bicep runbook which does the reverse peering as a separate post-provision step.
DESCRIPTION
}

variable "deployer_ip_address" {
  type        = string
  default     = null
  description = <<DESCRIPTION
Optional single public IP (no CIDR suffix) to temporarily allow onto the GenAI Key Vault data plane so a deployer outside the spoke VNet can complete data-plane steps during a demo. Mirrors the intent of Bicep allowedIpRanges.

Leave null for a strict Zero Trust posture (run all data-plane steps from the in-spoke jumpbox instead).
DESCRIPTION
}

variable "apim_publisher_email" {
  type        = string
  default     = "DoNotReply@bakermckenzie.com"
  description = "Publisher email for API Management."
}

variable "apim_publisher_name" {
  type        = string
  default     = "Baker McKenzie AI Platform"
  description = "Publisher name for API Management."
}
