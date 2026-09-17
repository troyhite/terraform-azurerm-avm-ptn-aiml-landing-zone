# Centralized Private DNS for the multi-sandbox gateway

When one hub fronts **many** Foundry sandboxes, Private DNS must be centralized. If
each sandbox creates its own copy of the `privatelink.*` zones and links them to the
shared hub VNet, the second sandbox fails — a VNet can link to only one zone per
namespace. Centralized DNS is therefore a **prerequisite** for the AI gateway to
resolve every sandbox's private Foundry, not an optional nicety.

This folder is a self-contained reference for that foundation, matching the Cloud
Adoption Framework guidance *"Private Link and DNS integration at scale."*

## What it deploys

- **One central set of `privatelink.*` zones** in the hub / connectivity subscription
  (a `networking-rg`), each linked to the hub VNet with registration disabled. Covers
  the Foundry dependency set: `cognitiveservices`, `openai`, `services.ai`, AI Search
  (`search`), Storage (`blob/file/queue/table/dfs/web`), Key Vault (`vaultcore`),
  Cosmos (`documents` + the Cosmos API zones), `azurecr`, `azure-api`, `azconfig`.
- A **custom policy initiative** ([`initiative-definitions.json`](./initiative-definitions.json))
  bundling the built-in `DeployIfNotExists` policies for Cognitive/AI Services, AI
  Search, Key Vault, Storage blob, and Cosmos (Sql) — each pointed at the matching
  central zone — so any new private endpoint auto-registers with no manual DNS wiring.
- The assignment's **managed identity** granted **Network Contributor** (subscription)
  and **Private DNS Zone Contributor** (the zones' resource group).
- An **Azure Private DNS Resolver** in the hub as the resolution front door for
  on-premises and cross-spoke lookups (point on-premises conditional forwarders for
  the Azure public suffixes at its inbound endpoint IP).

## Scope

This reference assigns the initiative at **subscription** scope so it can be run
standalone. In a platform landing zone, assign the **same** initiative at the
**platform / connectivity management group** so every landing-zone subscription
inherits it automatically — the mechanism is identical; only the scope moves up. This
is a platform-team control, not a per-workload one.

## Reproduce

```powershell
$hub = "<hub-subscription-id>"; $rg = "networking-rg"; $hubVnetId = "<hub-vnet-resource-id>"

# 1. Central zones (loop over the privatelink.* set) + VNet links to the hub VNet
#    az network private-dns zone create -g $rg -n <zone>
#    az network private-dns link vnet create -g $rg -z <zone> -n hub-link -v $hubVnetId -e false

# 2. Initiative + assignment (edit initiative-definitions.json to point at your zones first)
az policy set-definition create --name hub-central-private-dns `
  --display-name "Hub - Configure private endpoints to use central private DNS zones" `
  --definitions "@initiative-definitions.json" --subscription $hub

az policy assignment create --name hub-central-dns `
  --policy-set-definition "/subscriptions/$hub/providers/Microsoft.Authorization/policySetDefinitions/hub-central-private-dns" `
  --scope "/subscriptions/$hub" --mi-system-assigned --location <region>

# 3. Grant the assignment's managed identity its roles
$mi = az policy assignment show --name hub-central-dns --scope "/subscriptions/$hub" --query identity.principalId -o tsv
az role assignment create --assignee-object-id $mi --assignee-principal-type ServicePrincipal `
  --role 4d97b98b-1d4f-4787-a291-c67834d212e7 --scope "/subscriptions/$hub"                       # Network Contributor
az role assignment create --assignee-object-id $mi --assignee-principal-type ServicePrincipal `
  --role b12aa53e-6015-4669-85d0-8515ebb3ae7f --scope "/subscriptions/$hub/resourceGroups/$rg"    # Private DNS Zone Contributor
```

## Onboarding a sandbox onto the central zones

For each sandbox private endpoint, create a **Private DNS zone group** pointing at the
central zone (the DINE policy does this automatically when assigned at the right
scope). The Foundry account endpoint registers into three zones —
`cognitiveservices`, `openai`, and `services.ai`. Then link the sandbox spoke VNet to
the central zones (not to per-spoke copies), so the hub and every spoke resolve the
private endpoints through the single central set.

> A standalone sandbox that keeps its own zones (linked only to its own VNet) still
> resolves for itself, but the hub cannot resolve it — which is why centralized DNS is
> required for the shared-gateway pattern.
