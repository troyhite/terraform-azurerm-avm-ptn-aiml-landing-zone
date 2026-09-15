# =====================================================================
# STACK B - Foundry sandbox: the intake contract
# =====================================================================
# Every variable below is a governance decision the customer must make BEFORE a
# sandbox can exist. This file is the demo's centerpiece: onboarding a new team
# means copying terraform.tfvars, changing a handful of these values, and running
# `terraform apply`. Read the comments aloud during the workshop.
# =====================================================================

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Controls AVM module telemetry. See https://aka.ms/avm/telemetryinfo."
}

# --- SANDBOX IDENTITY (the "who and what") ---------------------------

variable "team_name" {
  type        = string
  default     = "applied-ai"
  description = <<DESCRIPTION
The internal team that owns this sandbox. Baker McKenzie has multiple AI
constituencies (internal-ai, client-innovation, applied-ai, danielle). Drives
resource naming, tags, and the gateway product/subscription in Stack A.
Keep it short and lowercase - it seeds the resource name prefix.
DESCRIPTION
  validation {
    condition     = can(regex("^[a-z0-9-]{2,12}$", var.team_name))
    error_message = "team_name must be 2-12 lowercase alphanumeric/hyphen characters."
  }
}

variable "use_case" {
  type        = string
  default     = "contract-analysis"
  description = "The specific workload this sandbox serves. Tag + naming input; anchors showback to a purpose, not just a team."
}

variable "matter_id" {
  type        = string
  default     = "none"
  description = <<DESCRIPTION
Optional matter/engagement identifier. For a law firm this is the ethical-wall
anchor: when a sandbox is scoped to a client matter, data resources are named and
isolated per matter so one team/matter cannot see another's data. "none" for
internal, non-client use cases.
DESCRIPTION
}

variable "environment" {
  type        = string
  default     = "sandbox"
  description = <<DESCRIPTION
The lifecycle posture. This is the experimentation-to-production toggle:
- sandbox    : looser dev SKUs, shorter retention, meant for POCs.
- production : hardened defaults, longer retention, stricter budgets.
Same code, two postures - that IS the promotion story. Promotion in reality is a
governance review + a re-apply into a production subscription, not a live migration.
DESCRIPTION
  validation {
    condition     = contains(["sandbox", "production"], var.environment)
    error_message = "environment must be 'sandbox' or 'production'."
  }
}

variable "owner_email" {
  type        = string
  default     = "owner@bakermckenzie.com"
  description = "Accountable owner for this sandbox. A sandbox cannot exist without a named owner. Tag + budget alert recipient."
}

variable "developer_group_object_id" {
  type        = string
  default     = null
  description = <<DESCRIPTION
Entra ID GROUP object ID for this team's developers. Granted the "Azure AI
Developer" role on the sandbox Foundry account (least privilege, scoped to this
team only - the ethical wall between teams). This is what makes the sandbox
actually self-service: developers sign in as themselves (Entra, no keys) and
build in the Foundry portal / playground / agents. Layer Conditional Access, MFA,
and PIM on the group in Entra for the full secure posture. Null = no developer
access is granted by Terraform (you would assign roles manually).
DESCRIPTION
}

variable "cost_center" {
  type        = string
  default     = "legal-tech-0000"
  description = "Chargeback/showback anchor. Every resource is tagged with this so Derrick's cost view is a single tag filter."
}

# --- DATA RESIDENCY & ETHICAL WALLS (defaulted strict) ---------------

variable "data_classification" {
  type        = string
  default     = "confidential"
  description = <<DESCRIPTION
Sensitivity of the data this sandbox will touch. For Baker McKenzie the default
is intentionally strict (confidential). This value should drive how tightly the
sandbox is locked down and, in a fuller implementation, which regions and model
deployment types are permitted.
DESCRIPTION
  validation {
    condition     = contains(["public", "internal", "confidential", "highly-confidential"], var.data_classification)
    error_message = "data_classification must be public, internal, confidential, or highly-confidential."
  }
}

variable "model_deployment_type" {
  type        = string
  default     = "DataZoneStandard"
  description = <<DESCRIPTION
Azure OpenAI deployment type. DataZoneStandard keeps data processing within the
Azure geography (data residency) - the right default for confidential legal data.
GlobalStandard is cheaper/higher-capacity but can process in any geography. Flip
to GlobalStandard only for non-confidential use cases.
DESCRIPTION
  validation {
    condition     = contains(["DataZoneStandard", "GlobalStandard", "Standard"], var.model_deployment_type)
    error_message = "model_deployment_type must be DataZoneStandard, GlobalStandard, or Standard."
  }
}

# --- GOVERNANCE GUARDRAILS -------------------------------------------

variable "allowed_models" {
  type        = list(string)
  default     = ["gpt-4.1", "text-embedding-3-large"]
  description = <<DESCRIPTION
The model allow-list for this sandbox. Rendered both as the actual Foundry model
deployments AND (in governance.tf) as an Azure Policy assignment on the sandbox
resource group - the "governed model catalog" as code. Defaults cover chat +
embeddings (RAG). Add/remove to show the catalog changing.
DESCRIPTION
}

variable "enforce_model_policy_effect" {
  type        = string
  default     = "Audit"
  description = <<DESCRIPTION
The Azure Policy effect for the model allow-list. Start with Audit so teams can
discover what they need, then move to Deny to enforce. This mirrors the real
audit-then-deny governance rollout and pairs with the live proof (in the demo
sub) that platform policy overrides operator intent.
DESCRIPTION
  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.enforce_model_policy_effect)
    error_message = "enforce_model_policy_effect must be Audit, Deny, or Disabled."
  }
}

variable "enable_content_safety" {
  type        = bool
  default     = true
  description = "Deploy Azure AI Content Safety alongside Foundry. Extra relevant for privileged legal content (prompt shields, groundedness, protected material)."
}

# --- POSTURE A' (private mesh): hub gateway reachability -------------
# Foundry is always private in this module (create_private_endpoints is
# hardcoded true). The hub APIM (Stack A) reaches it over a PRIVATE path, so the
# sandbox must (1) peer its VNet to the hub and (2) link its private DNS zones to
# the hub VNet so APIM resolves the Foundry private endpoint.

variable "hub_vnet_resource_id" {
  type        = string
  description = <<DESCRIPTION
Resource ID of the hub VNet that hosts the AI Gateway (Stack A APIM). The sandbox
peers to it and links its private DNS zones to it, so the hub APIM can resolve and
reach the sandbox Foundry private endpoint. Cross-subscription (same tenant) is fine.
DESCRIPTION
}

variable "create_reverse_hub_peering" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
Whether Terraform also creates the reverse hub -> sandbox peering. Requires write
access to the hub VNet's resource group. You own the homelab hub, so true is fine.
Set false if a separate platform team owns the hub and will create the reverse peering.
DESCRIPTION
}

# --- COST GUARDRAILS -------------------------------------------------

variable "monthly_budget_usd" {
  type        = number
  default     = 500
  description = "Monthly budget for the sandbox resource group. The sandbox self-polices spend; alerts fire to the owner + platform cost lead."
}

variable "budget_alert_emails" {
  type        = list(string)
  default     = ["owner@bakermckenzie.com"]
  description = "Recipients for budget threshold alerts (owner + platform cost lead, e.g. Derrick)."
}

# --- OPTIONAL SERVICES -----------------------------------------------

variable "enable_cosmos" {
  type        = bool
  default     = false
  description = <<DESCRIPTION
Whether to deploy Cosmos DB (Foundry thread/agent state store). Wired into the
template but OFF by default to keep the demo deploy lean and fast. Set true to
show the full agent-state footprint.
DESCRIPTION
}

# --- PLACEMENT & NAMING ----------------------------------------------

variable "location" {
  type        = string
  default     = "centralus"
  description = "Azure region for the sandbox. Central US for this engagement. In a fuller implementation, data_classification would constrain the allowed regions."
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "Sandbox resource group name. If null, a name is generated from team/use-case. Must not already exist."
}

variable "spoke_vnet_address_space" {
  type        = list(string)
  default     = ["192.168.0.0/23"]
  description = "Address space for the sandbox VNet. Standalone here (no hub peering under posture A), but keep it non-overlapping in case you later peer."
}
