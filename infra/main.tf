data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "main" {
  name     = local.names.rg
  location = var.location
  tags     = local.tags
}
