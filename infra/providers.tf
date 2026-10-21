# In the pipeline, authentication comes from the environment:
# ARM_USE_OIDC=true, ARM_CLIENT_ID and ARM_TENANT_ID (GitHub OIDC token,
# no secrets). Locally, it falls back to the Azure CLI login.
provider "azurerm" {
  features {}

  subscription_id     = var.subscription_id
  storage_use_azuread = true
}
