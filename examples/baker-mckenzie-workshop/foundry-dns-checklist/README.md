# Foundry Private DNS coverage checklist

**For environments that already centralize Private DNS.** If you run a platform
landing zone with centralized `privatelink.*` zones and a Private DNS Resolver (the
typical mature setup — central zones in a connectivity/identity subscription, a
DeployIfNotExists policy that auto-registers private endpoints, and a resolver as the
front door), you do **not** need to build anything here. Use this as a **checklist** to
confirm your existing central DNS fully covers Azure AI Foundry before you deploy
sandboxes behind the gateway.

> New to centralized Private DNS, or don't have it yet? See the main README's
> "Centralized Private DNS: the prerequisite" section for the concept and why it is
> required for the multi-sandbox gateway.

## Why Foundry needs a checklist

A single **Azure AI Foundry (AI Services) account** registers into **three** private
DNS zones, not one. This is the most common gap — teams add `openai` and miss the
other two, and the Foundry portal/playground then fails to resolve privately:

| Foundry needs this zone | For |
| --- | --- |
| `privatelink.cognitiveservices.azure.com` | Cognitive Services / AI Services data plane |
| `privatelink.openai.azure.com` | Azure OpenAI data plane |
| `privatelink.services.ai.azure.com` | AI Services (Foundry) endpoint |

## Full namespace coverage checklist

Confirm your **central** zones include every namespace the Foundry sandbox
dependencies use (each linked to the hub and resolvable from where developers and the
gateway connect):

- [ ] `privatelink.cognitiveservices.azure.com` — Foundry
- [ ] `privatelink.openai.azure.com` — Foundry
- [ ] `privatelink.services.ai.azure.com` — Foundry
- [ ] `privatelink.search.windows.net` — Azure AI Search
- [ ] `privatelink.blob.core.windows.net` — Storage (blob)
- [ ] `privatelink.file.core.windows.net` — Storage (file)
- [ ] `privatelink.queue.core.windows.net` — Storage (queue)
- [ ] `privatelink.table.core.windows.net` — Storage (table)
- [ ] `privatelink.dfs.core.windows.net` — Storage (ADLS)
- [ ] `privatelink.vaultcore.azure.net` — Key Vault
- [ ] `privatelink.documents.azure.com` — Cosmos DB (SQL; agent memory)
- [ ] `privatelink.azurecr.io` — Container Registry (incl. the regional `*.data.azurecr.io` record)
- [ ] `privatelink.azconfig.io` — App Configuration
- [ ] `privatelink.azure-api.net` — API Management (the AI gateway)

## Confirm auto-registration (DINE policy)

Confirm your platform's **DeployIfNotExists** Private DNS policy set is assigned at the
**connectivity / platform management group** and points at the central zones, so a new
sandbox's private endpoints register automatically — no per-endpoint DNS wiring.

- [ ] Built-in *"Configure Cognitive Services accounts to use private DNS zones"* →
      cognitiveservices/openai/services.ai central zones
- [ ] *"Configure Azure AI Search services to use private DNS zones"* → search central zone
- [ ] *"Configure Azure Key Vaults to use private DNS zones"* → vaultcore central zone
- [ ] *"Configure CosmosDB accounts to use private DNS zones"* (group `Sql`) → documents central zone
- [ ] *"Configure a private DNS Zone ID for blob groupID"* → blob central zone

[`initiative-definitions.json`](./initiative-definitions.json) is an **adaptable
example** of bundling those built-in DINE policies into a single initiative pointed at
your central zones — useful if you need to extend an existing assignment to cover the
Foundry namespaces. (It uses a `<hub-subscription-id>` placeholder; a platform team
would assign the equivalent at the management-group scope.)

## Confirm resolution reach

- [ ] The hub / central **Private DNS Resolver** (or DNS proxy) resolves the private
      endpoints for cross-spoke lookups.
- [ ] **On-premises** clients resolve the Foundry endpoints privately — point
      conditional forwarders for the Azure public suffixes (e.g. `openai.azure.com`,
      `cognitiveservices.azure.com`, `services.ai.azure.com`, `search.windows.net`,
      `vault.azure.net`, `blob.core.windows.net`, `documents.azure.com`) at the
      resolver's inbound endpoint IP.

## In the module

When a sandbox deploys into an environment with centralized, policy-managed DNS, set
the module's platform-landing-zone mode so it registers into the central zones instead
of creating its own (Terraform `private_dns_zones.azure_policy_pe_zone_linking_enabled
= true`; Bicep `ailz-integrated` + `policyManagedPrivateDns`). The standalone mode
(used by this example's sandbox for a self-contained deployment) creates per-sandbox
zones and does not scale across many sandboxes on one hub.
