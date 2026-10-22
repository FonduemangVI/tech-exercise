# Diagnostic settings for every resource that supports them, all to the one
# Log Analytics workspace. Add each new resource to diag_targets as it is
# built. Map keys are static, so for_each works even though IDs are only
# known at apply.
#
# Logs go to resource-specific tables (AZKVAuditLogs, AKSAuditAdmin and so
# on), not the shared AzureDiagnostics table: typed columns, per-table
# retention and plans, and no 500-column limit. Only Key Vault and AKS offer
# the choice and default to AzureDiagnostics, so only they set
# "Dedicated". ACR, blob and the workspace always use their own tables; NSGs
# and public IPs only have AzureDiagnostics. Setting "Dedicated" where the
# choice does not exist gives a permanent plan diff.

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

    # Registry logins, pushes and pulls
    acr = azurerm_container_registry.main.id
  }

  # Targets that offer resource-specific tables but default to AzureDiagnostics
  diag_dedicated = toset(["kv"])

  # Azure stores AllMetrics on the blob service as its two categories, so
  # naming them avoids a permanent plan diff
  diag_metrics = {
    blob = ["Capacity", "Transaction"]
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

  name                           = "${local.prefix}-diag"
  target_resource_id             = each.value
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
  log_analytics_destination_type = contains(local.diag_dedicated, each.key) ? "Dedicated" : null

  enabled_log {
    category_group = "allLogs"
  }

  dynamic "enabled_metric" {
    for_each = toset(lookup(local.diag_metrics, each.key, ["AllMetrics"]))

    content {
      category = enabled_metric.value
    }
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

# AKS gets its own setting with explicit categories: allLogs would include
# kube-audit (every read), which is very high volume for a 1 GB/day cap.
#   kube-audit-admin  every change (create, update, delete), incl. RBAC and Secrets (AKSAuditAdmin)
#   guard             Entra ID and Azure RBAC authorisation decisions (AKSControlPlane)
#   kube-apiserver    API server logs (AKSControlPlane)
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                           = "${local.prefix}-diag"
  target_resource_id             = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "guard"
  }

  enabled_log {
    category = "kube-apiserver"
  }
}
