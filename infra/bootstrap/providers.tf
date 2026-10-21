provider "azurerm" {
  features {}

  subscription_id = var.subscription_id

  # The state storage account has shared keys disabled, so all data-plane
  # access uses Entra ID.
  storage_use_azuread = true
}
