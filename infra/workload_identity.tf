# Workload identities: Kubernetes service accounts exchange their token for
# an Entra ID token through the cluster's OIDC issuer. No secrets stored.

# Flux source-controller pulls Helm charts and OCI artefacts from ACR.
# The other Flux controllers never talk to Azure.
resource "azurerm_user_assigned_identity" "flux" {
  name                = "id-flux"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "flux_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.flux.principal_id
}

resource "azurerm_federated_identity_credential" "flux_source_controller" {
  name                      = "flux-source-controller"
  user_assigned_identity_id = azurerm_user_assigned_identity.flux.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject                   = "system:serviceaccount:flux-system:source-controller"
}

# tasky reads its Mongo URI and JWT secret from Key Vault through the
# Secrets Store CSI driver.
resource "azurerm_user_assigned_identity" "tasky" {
  name                = "id-tasky"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "tasky_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.tasky.principal_id
}

resource "azurerm_federated_identity_credential" "tasky" {
  name                      = "tasky"
  user_assigned_identity_id = azurerm_user_assigned_identity.tasky.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject                   = "system:serviceaccount:tasky:tasky-sa"
}
