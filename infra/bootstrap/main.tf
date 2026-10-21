data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

locals {
  # Same convention as infra/naming.tf
  prefix         = "wiz-ex-${var.location_short}"
  prefix_compact = replace(local.prefix, "-", "")

  tags = {
    Project     = "wiz-exercise"
    Environment = "exercise"
    Owner       = var.owner_tag
    ManagedBy   = "terraform"
    Repo        = "github.com/${var.github_owner}/${var.github_repo}"
    Component   = "bootstrap"
  }
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# Kept separate from the main resource group, so destroying the
# environment never deletes the Terraform state or pipeline identities.
resource "azurerm_resource_group" "bootstrap" {
  name     = "${local.prefix}-bootstrap-rg"
  location = var.location
  tags     = local.tags
}

# ---------- Terraform state storage ----------

# Accepted risk OPS-1 (docs/risk-register.md): the public endpoint stays
# reachable because GitHub-hosted runners have no fixed IPs. Compensating
# controls: Entra ID only (shared keys off), no anonymous access, TLS 1.2,
# RBAC scoped to the tfstate container, versioning and soft delete.
#trivy:ignore:AZU-0012:exp:2026-12-31
resource "azurerm_storage_account" "tfstate" {
  name                = "${local.prefix_compact}tfst${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = azurerm_resource_group.bootstrap.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false # Entra ID only
  allow_nested_items_to_be_public   = false
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# Lets the person running bootstrap use the remote state from a laptop.
resource "azurerm_role_assignment" "tfstate_current_user" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
