# =====================================================================
# STACK B - AI Search -> Storage RBAC (playground data-flow fix)
# =====================================================================
# The AI Landing Zone module grants the Foundry PROJECT identity access to the
# sandbox storage account, but it does NOT grant the AI SEARCH service's own managed
# identity access. Without that grant, the Search indexer cannot read/write blobs, so
# uploading + indexing data in the Foundry chat playground fails (verified live).
#
# This file closes the gap for future deployments: it discovers the search services
# and storage accounts the module created, then grants each Search service's managed
# identity "Storage Blob Data Contributor" on each sandbox storage account.
#
# HOW IT RESOLVES: the Search identity is discovered via data lookup after the module
# creates it. On a brand-new (greenfield) resource group, run `terraform apply` to
# create the resources, then apply again to reconcile this RBAC - the same two-pass
# flow this repo already uses to register a sandbox behind the gateway. (For a
# greenfield FIRST apply, keep grant_search_service_storage_access = false, then set
# it true and re-apply.) A Search service must have a system-assigned managed identity
# and RBAC enabled to receive the grant; services without one are skipped.
# =====================================================================

variable "grant_search_service_storage_access" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
Grant each AI Search service's managed identity "Storage Blob Data Contributor" on the
sandbox storage account(s). Closes the AI Landing Zone module gap that otherwise breaks
Foundry chat-playground indexing (the module wires the Foundry project identity to
storage but not the Search service's own identity). Resolved via data lookup, so it
applies on a reconciling `terraform apply` once Search + Storage exist. Set false to
let a platform team manage this grant separately.
DESCRIPTION
}

# Storage accounts + search services the module created in this resource group.
data "azurerm_resources" "sandbox_storage" {
  count               = var.grant_search_service_storage_access ? 1 : 0
  resource_group_name = local.resource_group_name
  type                = "Microsoft.Storage/storageAccounts"
}

data "azurerm_resources" "sandbox_search" {
  count               = var.grant_search_service_storage_access ? 1 : 0
  resource_group_name = local.resource_group_name
  type                = "Microsoft.Search/searchServices"
}

# Read each search service so we can get its system-assigned managed identity.
data "azurerm_search_service" "sandbox" {
  for_each            = var.grant_search_service_storage_access ? { for r in one(data.azurerm_resources.sandbox_search[*])["resources"] : r.name => r.name } : {}
  name                = each.value
  resource_group_name = local.resource_group_name
}

locals {
  # Storage account resource IDs discovered in the sandbox RG.
  search_rbac_storage_ids = var.grant_search_service_storage_access ? [
    for r in one(data.azurerm_resources.sandbox_storage[*])["resources"] : r.id
  ] : []

  # Search services that actually have a system-assigned managed identity (skip any
  # without one - they need the identity enabled before they can be granted a role).
  search_rbac_principals = {
    for name, s in data.azurerm_search_service.sandbox :
    name => try(s.identity[0].principal_id, null)
    if try(s.identity[0].principal_id, null) != null
  }

  # (search identity) x (storage account) grants.
  search_rbac_grants = {
    for g in flatten([
      for sname, pid in local.search_rbac_principals : [
        for sid in local.search_rbac_storage_ids : {
          key          = "${sname}|${sid}"
          principal_id = pid
          scope        = sid
        }
      ]
    ]) : g.key => g
  }
}

resource "azurerm_role_assignment" "search_to_storage" {
  for_each = local.search_rbac_grants

  scope                = each.value.scope
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value.principal_id
  principal_type       = "ServicePrincipal"
}
