# Hub centralized Private DNS (DINE)

The centralized Private DNS authority for the demo hub, matching CAF
"Private Link and DNS integration at scale". This is what lets the hub AI gateway
resolve **every** sandbox's private Foundry with no per-spoke zone collisions.

## What is deployed (hub subscription, `networking-rg`)

- **21 central `privatelink.*` zones**, each VNet-linked to `homelab-vnet`
  (registration disabled). Covers Foundry (`cognitiveservices`, `openai`,
  `services.ai`), AI Search, Storage (`blob/file/queue/table/dfs/web`), Key Vault
  (`vaultcore`), Cosmos (`documents` + API zones), `azurecr`, `azure-api`, `azconfig`.
- Custom initiative **`hub-central-private-dns`** = the built-in `DeployIfNotExists`
  policies for Cognitive/AI Services, AI Search, Key Vault, Storage blob, and Cosmos
  (Sql), each pointed at the matching central zone. See
  [`initiative-definitions.json`](./initiative-definitions.json).
- Assignment **`hub-central-dns`** at **subscription scope** with a system-assigned
  managed identity holding **Network Contributor** (subscription) + **Private DNS
  Zone Contributor** (`networking-rg`).
- Resolution front door: existing hub **Azure Private DNS Resolver** inbound
  endpoint.

## Scope note

Assigned at **subscription** scope here because the sponsored demo subscriptions
can't be re-parented under a management group. In production this same assignment
goes at the **platform / connectivity management group** so every landing-zone
subscription inherits it. Same mechanism, higher scope.

## Reproduce

```powershell
$hub = "<hub-subscription-id>"; $rg = "networking-rg"

# 1. Central zones (loop over the privatelink.* set) + VNet links to the hub VNet
#    az network private-dns zone create -g $rg -n <zone>
#    az network private-dns link vnet create -g $rg -z <zone> -n homelab-vnet-link -v <hubVnetId> -e false

# 2. Initiative + assignment
az policy set-definition create --name hub-central-private-dns `
  --display-name "Hub - Configure private endpoints to use central private DNS zones" `
  --definitions "@initiative-definitions.json" --subscription $hub

az policy assignment create --name hub-central-dns `
  --policy-set-definition "/subscriptions/$hub/providers/Microsoft.Authorization/policySetDefinitions/hub-central-private-dns" `
  --scope "/subscriptions/$hub" --mi-system-assigned --location centralus

# 3. Grant the assignment's managed identity its roles
$mi = az policy assignment show --name hub-central-dns --scope "/subscriptions/$hub" --query identity.principalId -o tsv
az role assignment create --assignee-object-id $mi --assignee-principal-type ServicePrincipal `
  --role 4d97b98b-1d4f-4787-a291-c67834d212e7 --scope "/subscriptions/$hub"                       # Network Contributor
az role assignment create --assignee-object-id $mi --assignee-principal-type ServicePrincipal `
  --role b12aa53e-6015-4669-85d0-8515ebb3ae7f --scope "/subscriptions/$hub/resourceGroups/$rg"    # Private DNS Zone Contributor
```

> The standalone spoke is untouched — its zones link only to its own
> spoke VNet, so this hub-level centralization does not affect it.

## Migrated spoke: Stack B (`vnet-ailz-applied`)

Stack B was deployed standalone (`private_dns_zones = {}`), which left its 21 local
`privatelink.*` zones **empty of A-records** — its private endpoints had no working
private DNS. It was migrated onto the central zones:

1. Created a **PE DNS zone group on each of the 11 private endpoints** pointing at the
   hub central zones (Foundry account PE → `cognitiveservices` + `openai` +
   `services.ai`; Cosmos → `documents` with regional records auto-created; ACR →
   `azurecr` with the data endpoint auto-created; plus Search, Blob, Key Vault,
  App Config). This auto-populated the central zones with **18 private A-records**
  and is self-maintaining.
2. **Relinked the spoke VNet**: removed its links to the 21 local zones, then linked
   it to the 21 central zones (no collision once the local links were gone). Every
   central zone now carries **both** the hub and the Stack B spoke link.
3. **Deleted the 21 now-empty local zones** in `rg-ailz-applied-ka3pt`.

Net result: the hub (and the future AI gateway) resolves Stack B's private Foundry,
Search, Cosmos, Storage, Key Vault, ACR, and App Config endpoints through the single
central zone set. Because the DINE policy is hub-subscription-scoped, this cross-sub
spoke was wired **manually** (exactly what the policy would do at management-group
scope in production).

