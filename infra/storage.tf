# Backup storage. W6: the backups container allows anonymous read and
# list, intentionally, as required by the brief. See docs/issue-register.md.
#
# Everything else is locked down: no shared keys (Entra ID only, the VM
# writes with its managed identity), TLS 1.2, soft delete. Anonymous read
# needs no key, so the weakness works exactly as specified.

#trivy:ignore:AZU-0012
resource "azurerm_storage_account" "backup" {
  name                     = local.names.storage
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true # portal uses Entra ID, not the disabled keys
  infrastructure_encryption_enabled = true
  public_network_access             = "Enabled" # W6: anonymous access from the internet
  allow_nested_items_to_be_public   = true      # W6: lets the container below be public

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

# W6: anonymous read and list
#trivy:ignore:AZU-0007
resource "azurerm_storage_container" "backups" {
  name                  = "backups"
  storage_account_id    = azurerm_storage_account.backup.id
  container_access_type = "container"
}

# Admin can list and download the backups with Entra ID, to check they run.
# Read only, on this container only: no write or delete, so a stolen admin
# session cannot tamper with the backups.
resource "azurerm_role_assignment" "admin_backup_reader" {
  scope                = azurerm_storage_container.backups.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.admin_object_id
}
