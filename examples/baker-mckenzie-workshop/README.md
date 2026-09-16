# Baker McKenzie AI Landing Zone workshop

A tailored, two-stack Terraform example for the Foundry governance / AI sandbox
workshop. It demonstrates the **AI Gateway Landing Zone** pattern: many governed
Foundry sandboxes (one per team / subscription) fronted by a single shared API
Management gateway in the hub.

> This is a workshop/demo asset. It is built on the Azure AI Landing Zone AVM
> module (`../../`) and follows the Microsoft best-practice patterns at
> <https://azure.github.io/AI-Landing-Zones/>.

## The story it tells

1. **Governed sandbox as a product.** A team gets a Foundry environment only by
   filling an *intake contract* (owner, data classification, residency, model
   allow-list, budget). No sandbox exists without those decisions.
2. **Isolation and residency by default.** Foundry is private; models default to
   **DataZone** deployments (data stays in-geo); data resources are per-team - the
   ethical-wall / client-confidentiality story for a law firm.
3. **Secure self-service for developers.** Developer teams sign in to *their* sandbox
   Foundry directly - portal, playground, agents, prompt flow, VS Code - to build and
   experiment. "Secure" means Entra ID auth (no keys), least-privilege RBAC scoped to
   their own project, Conditional Access / MFA, and private networking - not a locked
   door. Teams get in and build; the guardrails travel with them.
4. **A governed runtime front door (optional, for apps).** When apps or shared
   consumers need model inference, they go through one hub APIM gateway with per-team
   keys, token limits (fair use), and per-team token metrics (showback). This is a
   *runtime* concern - it is not how a developer experiments, and it is not required
   to use the sandbox.
5. **Governance as code + enforced by platform.** The model allow-list is also an
   Azure Policy (audit -> deny). Reinforced by the live proof that a management-
   group policy overrode even an Owner (see the governed-subscription note below).

## Two access planes (read this before the architecture)

The single most important framing: there are **two** ways into a sandbox, and they
are different.

| Plane | Who | How | Secured by |
| --- | --- | --- | --- |
| **Developer / build** (primary) | Developer teams (humans) | Directly into their sandbox Foundry - portal, playground, agents, notebooks | Entra ID + least-privilege RBAC on their project, Conditional Access/MFA, private network access |
| **Application / runtime** (secondary) | Deployed apps + shared consumers | Through the hub APIM gateway | Per-team subscription key + Entra, token limits, MI auth, token metrics (showback) |

The gateway governs *runtime consumption*. Developers experimenting do **not** go
through it - they use their sandbox Foundry directly, secured by identity and network.

## Architecture

![Hub-and-spoke AI gateway architecture](diagrams/hub-and-spoke-gateway.drawio.png)

- **Developer plane (solid, left):** teams reach *their* Foundry directly and securely.
- **Runtime plane (right):** apps call models through the hub gateway.
- **Stack A** (`01-hub-ai-gateway/`) - deploy **once** into the hub subscription (runtime plane).
- **Stack B** (`02-foundry-sandbox/`) - deploy **per team**, each in its own sub.
- Live demo deploys Stack A + one Stack B; teams 2/3 are shown via config + diagram.

## How developers reach a private Foundry

Because the sandbox Foundry is **private** (private endpoints, no public data plane),
developer access must originate from a network that can route to and resolve the
private endpoint. Choose one (this is a real design decision for the customer):

- **Cloud PC (Windows 365) or Azure Virtual Desktop** joined to a management VNet
  peered to the sandbox - developers get a browser inside the network. Cleanest for
  "many developers, no corporate ExpressRoute."
- **Corporate ExpressRoute / VPN + Azure Private DNS Resolver** in the hub - developers
  use their own laptops; the corp network resolves `privatelink.*` and routes to the
  private endpoints. Best long-term for an enterprise; more upfront networking.
- **Jumpbox + Bastion** in the sandbox/management VNet - fine for a few operators or a
  demo, not for a whole developer team. (Note: the AVM jump VM cannot be provisioned
  in a policy-locked subscription - see the governed-subscription section - so create
  it manually with an inline password, or use Cloud PC/AVD.)

Whichever path, access is still gated by **Entra ID + RBAC** (below): being on the
network is necessary but not sufficient.

## Developer access is RBAC, not keys

Set `developer_group_object_id` in the sandbox intake to the team's Entra ID **group**.
Stack B grants that group **Azure AI Developer** on the sandbox Foundry - least
privilege, scoped to this team's account/project only (ethical walls between teams).
Combined with `disable_local_auth = true` (no shared keys), developers authenticate as
themselves, and everything they do is attributable. Layer Conditional Access / MFA /
PIM on the group in Entra for the full "secure manner."

## Run order

```pwsh
# 0) Pre-register resource providers in EACH target subscription (see below).

# 1) Hub gateway - once, into the hub sub
cd 01-hub-ai-gateway
Copy-Item terraform.tfvars.example terraform.tfvars   # fill hub VNet + LAW ids
az account set --subscription <hub-sub-id>
terraform init; terraform apply        # leave registered_sandboxes empty for now

# 2) First sandbox - into a team sub
cd ../02-foundry-sandbox
Copy-Item terraform.tfvars.example terraform.tfvars   # fill team intake + hub VNet id
az account set --subscription <team-sub-id>
terraform init; terraform apply
terraform output register_in_stack_a   # copy this block

# 3) Register the sandbox behind the gateway - back in the hub sub
cd ../01-hub-ai-gateway
#   paste the block into registered_sandboxes in terraform.tfvars
az account set --subscription <hub-sub-id>
terraform apply                        # minutes - just adds backend/API/product/policy
```

**Demo-day tip:** deploy Stack A during your dry run and **leave it warm** - APIM
is the long pole. On the day you only deploy a fresh Stack B and re-apply the tiny
Stack A registration delta. Keep your tested deployment up as the fallback.

## Pre-register resource providers (per subscription)

```pwsh
foreach ($rp in "Microsoft.CognitiveServices","Microsoft.MachineLearningServices","Microsoft.Search","Microsoft.Storage","Microsoft.KeyVault","Microsoft.Network","Microsoft.App","Microsoft.ApiManagement","Microsoft.Web","Microsoft.OperationalInsights","Microsoft.Authorization","Microsoft.PolicyInsights","Microsoft.DocumentDB","Microsoft.ContainerRegistry") {
  az provider register --namespace $rp
}
```

## Permissions

Each deployer needs **Contributor + User Access Administrator** on the target
subscription (UAA is required for the RBAC assignments - Contributor alone gets a
403). For the reverse hub<->sandbox peering, you also need write access to the hub
VNet's resource group.

## Stack A gateway: hardening & proof (deployed live)

Stack A (the APIM StandardV2 hub gateway) was deployed into the demo hub and a live
chat completion was driven **through the gateway to Stack B's private Foundry** -
`gpt-4.1` replied and per-team token metrics flowed to the hub Log Analytics
workspace. That single call exercises the whole architecture: public gateway ->
subscription-key auth -> APIM **managed-identity** auth to the private Foundry ->
**central Private DNS** resolution -> **VNet integration + peering** to the private
endpoint at `192.168.8.x`.

Three StandardV2 VNet-integration gotchas were hardened into `01-hub-ai-gateway`
(each cost a failed apply first, so they're worth calling out):

1. **Subnet delegation** - the APIM integration subnet must be delegated to
   `Microsoft.Web/serverFarms`. (Classic Developer/Premium External injection must
   NOT have this delegation - the example toggles it on `apim_is_v2`.)
2. **`Microsoft.Web` resource provider** must be registered in the gateway
   subscription, or the create fails with `SubnetSubscriptionMustBeRegisteredWithMicrosoftWeb`.
   (Now in the pre-register list above.)
3. **An NSG is still required** on the integration subnet even for StandardV2
   (`NetworkSecurityGroupNotFound`), and APIM must depend on the NSG *association*
   explicitly - otherwise Terraform races the association and APIM deploys before the
   NSG is attached. The example adds `depends_on` on the association.

Fallback: if v2 VNet integration ever errors on a given provider version, set
`apim_sku = "Developer_1"` - the config drops the delegation and keeps the NSG
automatically.

## Key decisions baked in

| Area | Choice | Why |
| --- | --- | --- |
| Gateway<->Foundry | Private mesh (posture A') | This Terraform module deploys Foundry private-only (see the Bicep-vs-Terraform callout below), so the gateway reaches it privately. Better security for a law firm anyway. |
| APIM SKU | StandardV2 | Fast provision + VNet integration. Fallback: Developer_1 (classic injection) if v2 integration errors. |
| Models | gpt-4.1 + text-embedding-3-large | Sensible chat + RAG defaults. Chat uses DataZone; embeddings use Standard (broadest availability). |
| Cosmos | wired, disabled | Keeps the deploy lean. Set `enable_cosmos = true` to include agent state. |
| Promotion | `environment` posture toggle + diagram | Concept without a fragile live migration. |
| Data residency | DataZone + per-team isolation (default) | Ethical walls / client confidentiality. |

## Centralized Private DNS: the prerequisite for the multi-sandbox gateway

The single most important platform-foundation point for scaling this pattern.

**The problem (hit live during the deploy):** with `flag_platform_landing_zone =
false`, each sandbox creates its **own** copy of the `privatelink.*` Private DNS
zones. When a second sandbox on the **same hub** tries to link its copies, Azure
rejects it: *"A virtual network cannot be linked to multiple zones with overlapping
namespaces."* A hub VNet can link to only one zone per namespace. So naive
per-sandbox hub linking does not scale, and the hub cannot resolve every sandbox's
private Foundry - which is exactly what the AI gateway needs.

**Microsoft best practice (CAF: "Private Link and DNS integration at scale"):**
centralize Private DNS. One set of `privatelink.*` zones, owned by the platform /
connectivity subscription, deployed once. Three components:

1. **Central Private DNS zones** in the connectivity subscription (the hub). The hub
   VNet and every spoke VNet link to this *single* set - never per-spoke copies.
2. **Azure Policy `DeployIfNotExists`** assigned at the management-group level, which
   auto-creates a Private DNS Zone Group on *every* private endpoint pointing at the
   central zones. Teams deploy PEs freely; DNS is wired automatically, no collisions.
3. **Central DNS resolution** via a hub **Azure Private DNS Resolver** (or hub
   DNS/firewall proxy) so on-prem and cross-spoke lookups resolve the private
   endpoints.

**How this maps to the module:** `flag_platform_landing_zone = true` (Bicep's
`ailz-integrated` + `policyManagedPrivateDns`; Terraform
`private_dns_zones.azure_policy_pe_zone_linking_enabled = true`) is the
best-practice mode - the sandbox registers into the central zones instead of
creating its own. `flag_platform_landing_zone = false` (used for the standalone
sandbox here) is fine for a single isolated deployment but breaks the moment a
second sandbox attaches to the same hub.

**For Baker McKenzie's real environment, the prescriptive sequence is:**
1. Platform team stands up the central `privatelink.*` zones once in the
   connectivity subscription.
2. Assign the DINE Private DNS policy at the management-group scope so every team's
   private endpoints auto-register.
3. Each Foundry sandbox deploys with `flag_platform_landing_zone = true`, pointing
   at the central zones. Foundry, Search, Cosmos, Storage, and Key Vault private
   endpoints all resolve through the hub - and the AI gateway resolves every
   sandbox's Foundry with zero collisions.

The collision is the concrete evidence for *why* centralized DNS is a prerequisite,
not an optional nicety. **Discovery question:** does Baker McKenzie already have (or
want help standing up) centralized Private DNS zones + the DINE policy in their
platform landing zone? Their answer determines whether the gateway pattern is
production-ready or needs that foundation first.

### Reference implementation: proven in the demo hub

This exact pattern is stood up and running in the demo hub subscription, so the
workshop can show it, not just describe it:

- **21 central `privatelink.*` zones** live in the hub's `networking-rg` (Foundry:
  `cognitiveservices`, `openai`, `services.ai`; plus `search`, `blob/file/queue/table/dfs/web`,
  `vaultcore`, `documents` + the Cosmos API zones, `azurecr`, `azure-api`, `azconfig`).
  All **21 are VNet-linked to the hub VNet** with registration disabled.
- **A custom initiative** (`hub-central-private-dns`) bundles the built-in
  `DeployIfNotExists` policies for Cognitive/AI Services, AI Search, Key Vault,
  Storage blob, and Cosmos (Sql) - each pointed at the corresponding central zone -
  assigned **once** with a single **system-assigned managed identity**.
- The policy identity holds **Network Contributor** (subscription) + **Private DNS
  Zone Contributor** (`networking-rg`), so any new private endpoint in the governed
  scope auto-gets a Private DNS Zone Group pointing at the central zones - no manual
  per-PE DNS wiring.
- A hub **Azure Private DNS Resolver** (inbound endpoint) provides the cross-network
  resolution front door for on-prem / cross-spoke lookups.

**Scope caveat (say this out loud in the room):** in the demo hub the initiative is
assigned at **subscription scope** as a faithful reference - the tenant's sponsored
subscriptions can't be re-parented under a management group I control. In Baker
McKenzie's environment the *same* assignment lives at the **platform / connectivity
management group** so every landing-zone subscription auto-registers. The mechanism
is identical; only the scope moves up. That's a platform-team control, not a
per-workload one.

## Callout: Bicep vs Terraform - Foundry network posture (not at parity)

A sharp, verified talking point: the two **official** IaC implementations of this
same AI Landing Zone do **not** currently treat the Foundry account's network
posture the same way.

**Bicep** exposes network isolation as a first-class, top-level parameter and lets
you deploy Foundry **public or private** (it even defaults to public):

```
// bicep-ptn-aiml-landing-zone/main.bicep
param networkIsolation bool = false                                              // line 88 (defaults public)
var _publicNetworkAccess = (!_networkIsolation || _applyIpRules) ? 'Enabled' : 'Disabled'  // line 699
// line 97 states this applies to "the AI Foundry / Cognitive Services accounts"
```
Truth table (from the same file): `networkIsolation=false` -> Foundry **public**;
`networkIsolation=true` -> **private**; `networkIsolation=true` + `allowedIpRanges`
-> private + public IP allow-list.

**Terraform (this module)** deploys Foundry **private-only** through its public
interface. The underlying `avm-ptn-aiml-foundry` sub-module supports both (it has
`examples/public` and a `public_network_access_enabled` variable), but the
landing-zone wrapper:

- hardcodes `create_private_endpoints = true` (`main.foundry.tf:16`, not exposed), and
- does not surface the Foundry `public_network_access_enabled` toggle, so it stays
  `null` and the sub-module resolves it to `publicNetworkAccess = "Disabled"`:

```
// avm-ptn-aiml-foundry/locals.foundry.tf
ai_foundry_public_network_access = (
  var.ai_foundry.public_network_access_enabled == null ?
  (var.create_private_endpoints ? "Disabled" : "Enabled") :   // -> Disabled here
  (var.ai_foundry.public_network_access_enabled ? "Enabled" : "Disabled"))
```

Net: **Bicep = choose public/private for Foundry; this Terraform module = Foundry
private-only** (other services like Key Vault / Storage / Search *do* expose public
toggles in Terraform - Foundry specifically does not). That is why this workshop's
gateway uses the private-mesh path (posture A').

**Say it precisely:** scope it to "the Terraform landing-zone module," not
"Terraform" in general, and version-stamp it ("as of the module version we
deployed") - these modules change quickly.

## Known constraint: governed (policy-locked) subscriptions

Some subscriptions inherit a management-group Azure Policy that **forces Key Vault
private-only** and cannot be overridden from inside the subscription (even
`az keyvault update --public-network-access Enabled` is refused; Owner does not
help). Observed first-hand in an MCAP demo subscription.

Impact: the AVM **build/jump VMs cannot be provisioned** there - during creation
they write their admin password into the private Key Vault from the deployer's
public IP, which the policy blocks (`403 ForbiddenByConnection`). This is external
governance, not a defect. Both VMs are therefore `deploy = false`.

**Use this as a live workshop moment:** the platform policy refuses to expose the
Key Vault regardless of operator rights - Zero Trust enforced by the platform, not
by trust. The tradeoff is that environment management happens over the private
network, not a public IP.

### Demoing the data plane

With the VMs off (and Foundry private), run a live data-plane action from a VM
**inside a VNet where the private endpoints resolve**:

- **Preferred - a VM in the sandbox VNet.** Create it manually (Portal/CLI), set
  the admin password inline (no Key Vault write, so the policy doesn't block it),
  pick any available size. Private endpoint FQDNs resolve automatically because the
  module linked the zones to the sandbox VNet. Reach it via Bastion.
- A VM in the hub VNet also works for reachability, but you must first link the
  sandbox's `privatelink.*` zones to the hub VNet (this example already links them
  to the hub for the gateway, so hub-side resolution works for the gateway path).

## Files

```
baker-mckenzie-workshop/
├── 01-hub-ai-gateway/       # Stack A: shared APIM front door
│   ├── main.tf              # APIM v2 + per-team backend/API/product/key/policy + RBAC
│   ├── variables.tf         # registered_sandboxes map
│   ├── outputs.tf           # gateway URL, example call
│   └── terraform.tfvars.example
└── 02-foundry-sandbox/      # Stack B: per-team governed Foundry landing zone
    ├── variables.tf         # THE INTAKE CONTRACT
    ├── main.tf              # AI LZ module (Foundry private, DataZone models, peering + DNS link)
    ├── governance.tf        # Azure Policy: model allow-list (audit -> deny)
    ├── cost.tf              # resource-group budget + alerts (showback)
    ├── outputs.tf           # values to register in Stack A
    └── terraform.tfvars.example
```

## Open items to revisit

- **Content Safety wiring:** `enable_content_safety` is in the intake contract as a
  discussion point; confirm the module surface for enforcing it per project.
- **Model asset IDs:** governance.tf allows any OpenAI-published model; tighten to
  exact `allowedAssetIds` (pinned versions) when the customer's catalog is set.

## Diagrams

`diagrams/` contains editable draw.io files with official Azure icons (rebuild with
`python diagrams/build.py`):

- `hub-and-spoke-gateway.drawio` - the AI Gateway Landing Zone: clients -> hub APIM
  -> per-team private Foundry sandboxes (solid = live, dashed = config + diagram).
- `promotion-lifecycle.drawio` - intake -> governed sandbox -> governance review ->
  production, with the guardrails that travel at every stage.
