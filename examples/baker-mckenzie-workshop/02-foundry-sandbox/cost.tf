# =====================================================================
# STACK B - Cost guardrail
# =====================================================================
# The sandbox self-polices spend. A resource-group budget with alerts to the
# owner + platform cost lead. This is the per-sandbox half of the
# showback story; the hub gateway (Stack A) adds per-team token metrics.
# =====================================================================

locals {
  # Budgets must start on the first of a month. Computed at plan time; changes are
  # ignored after creation so the value doesn't churn on later plans.
  budget_start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
}

resource "azurerm_consumption_budget_resource_group" "sandbox" {
  name              = "budget-${var.team_name}"
  resource_group_id = local.resource_group_id
  amount            = var.monthly_budget_usd
  time_grain        = "Monthly"

  time_period {
    start_date = local.budget_start_date
  }

  # Early-warning at 80% actual spend.
  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.budget_alert_emails
  }

  # At-limit alert at 100% actual spend.
  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.budget_alert_emails
  }

  # Production sandboxes also get a forecasted-overspend alert (posture toggle).
  dynamic "notification" {
    for_each = local.is_production ? [1] : []
    content {
      enabled        = true
      threshold      = 100
      operator       = "GreaterThan"
      threshold_type = "Forecasted"
      contact_emails = var.budget_alert_emails
    }
  }

  lifecycle {
    ignore_changes = [time_period]
  }

  depends_on = [module.ai_landing_zone]
}
