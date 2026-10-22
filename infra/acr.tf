# Container registry: the only image source for the cluster and for the
# Docker build base images (upstream images are copied in with az acr
# import). Basic SKU: no network rules or private endpoint, so access is
# Entra ID only with the admin user off. Accepted exception OPS-3 in
# docs/issue-register.md (public endpoint, registry-wide push).

resource "azurerm_container_registry" "main" {
  name                = local.names.acr
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Basic"
  admin_enabled       = false # no shared username and password; Entra ID only

  # Registry-wide roles (AcrPull, AcrPush), the model the role assignments
  # below and the AKS kubelet use. The ABAC mode would let AcrPush be
  # limited to the tasky repository; it needs the Container Registry
  # Repository Reader/Writer roles instead. Not done for the MVP: OPS-3.
  role_assignment_mode = "LegacyRegistryPermissions"

  tags = local.tags
}

# PR builds pull base images (no push: unreviewed code never publishes)
resource "azurerm_role_assignment" "pr_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = var.github_pr_principal_id
}

# The app pipeline on main pushes the tasky image
resource "azurerm_role_assignment" "app_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = var.github_app_principal_id
}
