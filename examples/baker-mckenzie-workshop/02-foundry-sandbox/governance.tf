# =====================================================================
# STACK B - Governance as code
# =====================================================================
# The allow-list of models isn't just a Terraform variable that renders model
# deployments - it's also enforced by Azure Policy on the sandbox resource group.
# This is the "governed model catalog" story: teams can only deploy approved
# models, and you roll it out audit-first, then flip to deny.
#
# Talking point: pair this with the live proof (in the demo subscription) that a
# management-group policy overrode even an Owner. Governance is enforced by the
# platform, not by trusting each team.
# =====================================================================

# Built-in: "[Preview]: Azure Machine Learning Deployments should only use
# approved Registry Models" - Foundry model deployments use the AML resource
# provider, so this governs Foundry model deployments too.
resource "azurerm_resource_group_policy_assignment" "allowed_models" {
  count = var.enforce_model_policy_effect == "Disabled" ? 0 : 1

  name                 = "allowed-ai-models"
  display_name         = "Allowed AI models - ${var.team_name} (${var.enforce_model_policy_effect})"
  description          = "Restricts model deployments in this sandbox to approved publishers. Audit-first, then Deny."
  resource_group_id    = local.resource_group_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/12e5dd16-d201-47ff-849b-8454061c293d"

  parameters = jsonencode({
    effect            = { value = var.enforce_model_policy_effect }
    allowedPublishers = { value = local.allowed_model_publishers }
    # Empty = allow any asset from the approved publishers. To pin exact models,
    # add asset IDs like:
    # azureml://registries/azure-openai/models/gpt-4.1/versions/2025-04-14
    allowedAssetIds = { value = [] }
  })

  # The resource group must exist before the assignment is scoped to it.
  depends_on = [module.ai_landing_zone]
}
