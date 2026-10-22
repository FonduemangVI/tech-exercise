# AKS: one node, Azure CNI Overlay with the Cilium data plane, API Server
# VNet Integration (public endpoint limited to the admin IP), Entra ID with
# Azure RBAC and no local accounts, OIDC issuer and workload identity.
#
# "Private subnet" (R14): nodes have no public IPs and sit in a subnet with
# no default outbound access; the API server lives in a delegated subnet.

# Control plane identity. Created before the cluster so it can be granted
# Network Contributor on its subnets first.
resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "aks_subnet" {
  for_each = {
    aks       = azurerm_subnet.aks.id
    apiserver = azurerm_subnet.apiserver.id
  }

  scope                = each.value
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = local.names.aks
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = local.names.aks
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"

  # Upgrades: automatic upgrades are off for the life of the exercise and
  # node OS patches apply in place (Unmanaged: no reimage), so nothing
  # changes under the demo. Planned with a 4 vCPU quota in mind (azurerm
  # has no max_unavailable, so every upgrade adds a surge node); the lab
  # turned out to allow 50 vCPUs, but fewer moving parts still wins.
  automatic_upgrade_channel = null
  node_os_upgrade_channel   = "Unmanaged"

  default_node_pool {
    name                        = "system"
    vm_size                     = var.aks_node_size
    node_count                  = 1
    vnet_subnet_id              = azurerm_subnet.aks.id
    os_disk_size_gb             = 64
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge = "1"
    }
  }

  # Required from azurerm 5.0. Manual: the node pool above is the only one;
  # no automatic node provisioning (it would need quota this lab lacks).
  node_provisioning_profile {
    mode = "Manual"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium" # available for pod-level rules (stretch: only tasky may reach Mongo)
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
    pod_cidr            = "10.244.0.0/16" # overlay range, not VNet addresses
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
  }

  api_server_access_profile {
    virtual_network_integration_enabled = true
    subnet_id                           = azurerm_subnet.apiserver.id
    authorized_ip_ranges                = var.admin_ip_cidrs
  }

  # Entra ID sign-in, Azure RBAC for Kubernetes authorisation, no local
  # (certificate) accounts: every kubectl call is tied to an identity.
  local_account_disabled            = true
  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  run_command_enabled       = true # app.yml deploys through az aks command invoke

  azure_policy_enabled = true # R27: allowed-images policy runs through this add-on

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  tags = local.tags

  depends_on = [azurerm_role_assignment.aks_subnet]
}

# Kubelet identity (created by AKS) pulls images
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                            = azurerm_container_registry.main.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# ---------------------------------------------------------------------------
# Who can use the cluster
# ---------------------------------------------------------------------------

# Me: full Kubernetes access through Entra ID, plus command invoke
resource "azurerm_role_assignment" "admin_aks" {
  for_each = toset([
    "Azure Kubernetes Service Cluster User Role",
    "Azure Kubernetes Service RBAC Cluster Admin",
    var.aks_command_invoke_role_name,
  ])

  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = each.value
  principal_id         = var.admin_object_id
}

# App pipeline: command invoke on the cluster, but Kubernetes rights only
# in the tasky namespace. Commands run as id-gh-app, so the namespace scope
# holds even through command invoke.
resource "azurerm_role_assignment" "app_aks_command_invoke" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = var.aks_command_invoke_role_name
  principal_id         = var.github_app_principal_id
}

resource "azurerm_role_assignment" "app_aks_user" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.github_app_principal_id
}

resource "azurerm_role_assignment" "app_aks_tasky_writer" {
  scope                = "${azurerm_kubernetes_cluster.main.id}/namespaces/tasky"
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = var.github_app_principal_id
}

# PR plans: refreshing the cluster calls listClusterUserCredential, which
# Reader does not include. Local accounts are off, so the credential is a
# kubeconfig with no secret in it (Entra ID login via kubelogin), and this
# identity has no Kubernetes RBAC role: it cannot read or change anything
# in the cluster.
resource "azurerm_role_assignment" "pr_aks_user" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.github_pr_principal_id
}
