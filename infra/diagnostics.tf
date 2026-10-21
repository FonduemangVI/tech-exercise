# Diagnostic settings for every resource that supports them, all to the one
# Log Analytics workspace. Add each new resource to diag_targets as it is
# built. Map keys are static, so for_each works even though IDs are only
# known at apply.

locals {
  diag_targets = {
    # Workspace audit logs: who ran which queries
    law = azurerm_log_analytics_workspace.main.id

    # Key Vault AuditEvent: every secret read and write, with the caller
    kv = azurerm_key_vault.main.id

    # Blob reads and writes, including anonymous reads of the backups (W6)
    blob = "${azurerm_storage_account.backup.id}/blobServices/default"

    # Mongo VM public IP (DDoS notifications and metrics)
    pip_vm = azurerm_public_ip.mongo.id

    # To add as they are built:
    # acr = azurerm_container_registry.main.id
  }

  # NSGs have no metrics and no documented category group, so they get
  # their own setting with explicit categories (resource below).
  diag_nsgs = {
    nsg_db  = azurerm_network_security_group.db.id
    nsg_aks = azurerm_network_security_group.aks.id
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = local.diag_targets

  name                       = "${local.prefix}-diag"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Which NSG rules applied to which NIC, and how often each rule matched
# (rule counters show hits on the open SSH rule, W4).
resource "azurerm_monitor_diagnostic_setting" "nsg" {
  for_each = local.diag_nsgs

  name                       = "${local.prefix}-diag"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }

  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}

# AKS gets its own setting with explicit categories (added with the cluster):
# allLogs would include kube-audit, which is very high volume.
