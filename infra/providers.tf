# In the pipeline, authentication comes from the environment:
# ARM_USE_OIDC=true, ARM_CLIENT_ID and ARM_TENANT_ID (GitHub OIDC token,
# no secrets). Locally, it falls back to the Azure CLI login.
provider "azurerm" {
  features {
    key_vault {
      # Purge protection is on, so a purge on destroy would fail. The vault
      # stays soft-deleted for 7 days and the random suffix avoids a clash.
      purge_soft_delete_on_destroy = false
    }
  }

  subscription_id     = var.subscription_id
  storage_use_azuread = true
}
