# R28 detective control: alert when the public backups container (W6) is
# read or listed without authentication. The brief requires the container
# to stay public, so the control is to know within minutes.
#
# The alert shows in the portal (Monitor > Alerts); no action group needed
# for the demo. Same query as docs/queries.md.

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "anonymous_backup_reads" {
  name                = "${local.prefix}-alert-anon-backup-reads"
  display_name        = "W6: anonymous read of database backups"
  description         = "Someone read or listed the public backups container without authentication. See docs/risk-register.md (W6)."
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  scopes              = [azurerm_log_analytics_workspace.main.id]
  severity            = 1

  # Logs arrive a few minutes late, so the window overlaps the frequency
  evaluation_frequency = "PT5M"
  window_duration      = "PT10M"

  criteria {
    query                   = <<-KQL
      StorageBlobLogs
      | where AuthenticationType == "Anonymous"
      | where OperationName in ("GetBlob", "ListBlobs", "GetBlobProperties")
      | where Uri has "/${azurerm_storage_container.backups.name}"
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  # StorageBlobLogs does not exist in the workspace until the first blob
  # log arrives, so the query cannot be validated at creation
  skip_query_validation   = true
  auto_mitigation_enabled = false

  tags = local.tags
}
