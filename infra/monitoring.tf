# ---------- Log Analytics ----------

resource "azurerm_log_analytics_workspace" "main" {
  name                = local.names.law
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  sku               = "PerGB2018"
  retention_in_days = var.log_retention_days
  daily_quota_gb    = var.law_daily_quota_gb

  # Entra ID only. The shared keys still sit in state (and so in any plan
  # file), but with local auth off they cannot write data into the
  # workspace, so nobody holding them can forge audit records. Nothing here
  # uses them: diagnostic settings, queries and alerts all go through Entra ID.
  local_authentication_enabled = false

  tags = local.tags
}

# ---------- Control plane audit logging (R26) ----------
# Sends the subscription Activity Log (every ARM write, delete and action,
# including role assignments and policy changes) to Log Analytics, where it
# can be queried and alerted on. The portal keeps only 90 days without this.

locals {
  activity_log_categories = [
    "Administrative",
    "Security",
    "ServiceHealth",
    "Alert",
    "Recommendation",
    "Policy",
    "Autoscale",
    "ResourceHealth",
  ]
}

resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "${local.prefix}-activity-log"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  dynamic "enabled_log" {
    for_each = toset(local.activity_log_categories)

    content {
      category = enabled_log.value
    }
  }
}
