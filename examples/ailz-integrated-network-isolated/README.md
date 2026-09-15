# AI Landing Zone — ailz-integrated + network isolation (Baker McKenzie)

This example configures the Terraform AI/ML Landing Zone to match the Bicep
implementation running in **`ailz-integrated`** deployment mode with
**`networkIsolation = true`**. It creates a spoke that peers to an existing
platform hub, reuses the hub's shared services, and keeps every PaaS data plane
private.

## Bicep → Terraform mapping

| Intent | Bicep (`docs/runbook-hub-spoke.md` §6) | This example |
| --- | --- | --- |
| Deployment mode | `DEPLOYMENT_MODE=ailz-integrated` | `flag_platform_landing_zone = true` |
| Peer to existing hub | `HUB_INTEGRATION_HUB_VNET_RESOURCE_ID` | `vnet_definition.vnet_peering_configuration.peer_vnet_resource_id` |
| Spoke→hub peering | `HUB_INTEGRATION_CREATE_HUB_PEERING=true` | `create_reverse_peering` (both directions when you have hub write access) |
| Network isolation | `NETWORK_ISOLATION=true` | module defaults (private endpoints, `public_network_access_enabled=false`); no "for testing" public overrides; APIM `Internal` + private |
| Reuse hub DNS zones | `existingPrivateDnsZone*` / `policyManagedPrivateDns` | `private_dns_zones.existing_zones_resource_group_resource_id` + `azure_policy_pe_zone_linking_enabled=true` |
| Hub DNS resolution | hub DNS via peering | `vnet_definition.dns_servers` = hub resolver/firewall DNS IPs |
| Reuse hub Log Analytics | `EXISTING_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID` | `law_definition.resource_id` |
| Reuse hub Bastion | `DEPLOY_BASTION=false` + `EXISTING_BASTION_RESOURCE_ID` | `bastion_definition.deploy = false` (hub Bastion reaches the spoke jumpbox over the peering) |
| Own jumpbox | `DEPLOY_JUMPBOX=true` | `jumpvm_definition.deploy = true` |
| No spoke firewall | `DEPLOY_AZURE_FIREWALL=false` | `firewall_definition.deploy = false` |

## Two behavior differences to know

1. **Egress routing to the hub firewall.** In the Terraform module, when
   `flag_platform_landing_zone = true` **no spoke route tables are created** —
   routing is expected to come from the platform hub. The Bicep
   `HUB_INTEGRATION_EGRESS_NEXT_HOP_IP` (force `0.0.0.0/0` through the hub
   firewall) has no direct spoke-created equivalent here; apply that UDR from the
   hub/platform side, or switch to a BYO-VNet where a `firewall_ip_address`
   route can be set.
2. **Reverse peering permissions.** `create_reverse_hub_peering = true` makes
   Terraform create the hub→spoke peering too, which needs write access to the
   hub VNet's resource group. If a separate platform team owns the hub, set it to
   `false` and have them create the reverse peering — this matches the Bicep
   runbook, which does the reverse peering as a separate post-provision step.

## Usage

```pwsh
cd examples/ailz-integrated-network-isolated
Copy-Item terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your real hub resource IDs
az login
terraform init
terraform plan
terraform apply
```

## Network isolation and the deployer

With isolation on, PaaS data planes are private. Control-plane (ARM) calls work
from anywhere, but some data-plane steps (AI Search, storage, Key Vault) need a
caller inside the spoke network. Run those from a jumpbox inside the spoke VNet.

## Known constraint: governed (policy-locked) subscriptions

Some subscriptions inherit an Azure Policy from their management group that
**forces Key Vault to private-only** and cannot be overridden from inside the
subscription (even `az keyvault update --public-network-access Enabled` is
refused, and Owner rights do not help). This was observed first-hand in an
MCAP-governed demo subscription.

Impact: the module's built-in **build VM and jump VM cannot be provisioned** in
such a subscription. During creation they write their generated admin password
into the GenAI Key Vault from the deployer's public IP; the private-only policy
blocks that data-plane write with `403 ForbiddenByConnection`. This is external
governance, not a module or config defect - no VM SKU or variable change fixes it.

What still works: the rest of the landing zone (~130 resources) deploys normally,
and the private Key Vault is the correct Zero Trust end state. This example
therefore ships with both VMs `deploy = false`.

Workshop talking point: this is a live example of platform-enforced Zero Trust -
the management-group policy refuses to expose the Key Vault publicly regardless
of the operator's rights. The tradeoff is that environment management happens
over the private network (a jumpbox / Bastion), never a public IP.

### Demoing the data plane anyway

To show a live private-endpoint data-plane action (Foundry playground chat, an
AI Search query, reading a secret), stand up a VM that lives inside a VNet where
the module-created Private DNS zones resolve:

- **Preferred - a VM in the spoke VNet.** Create it manually (Portal/CLI) and set
  the admin password inline so no Key Vault write is involved (that sidesteps the
  policy). The spoke VNet already has all `privatelink.*` zones linked, so private
  endpoint FQDNs resolve to private IPs automatically. Pick any size the Portal
  shows as available to avoid regional capacity limits.
- **A VM in the hub VNet** also works for network reachability (the spoke<->hub
  peering exists), **but** the module linked the Private DNS zones to the *spoke*
  VNet only. A hub VM will not resolve the private endpoint hostnames until those
  zones are also linked to the hub VNet (add virtual network links for each
  `privatelink.*` zone). Without that DNS link, the hub VM reaches the network but
  cannot resolve the private FQDNs.
