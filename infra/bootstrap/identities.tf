# GitHub Actions identities. Each one trusts a single GitHub OIDC subject, so
# a token from any other repo, branch, environment or event is rejected.
#
# | Identity    | Used by                          | Trusted subject                 |
# |-------------|----------------------------------|---------------------------------|
# | id-gh-infra | infra.yml apply on main          | environment:prod-infra          |
# | id-gh-app   | app.yml push and deploy on main  | environment:prod-app            |
# | id-gh-pr    | Plan and build jobs on PRs       | pull_request                    |
#
# Role assignments on ACR and AKS for id-gh-app and id-gh-pr are made in
# infra/, because those resources do not exist yet.

locals {
  github_issuer   = "https://token.actions.githubusercontent.com"
  github_audience = ["api://AzureADTokenExchange"]
  # Subject prefix from GitHub (immutable form with IDs), else the name-based form
  github_repo = coalesce(var.github_oidc_subject_prefix, "repo:${var.github_owner}/${var.github_repo}")

  pipeline_identities = {
    infra = {
      name    = "${local.prefix}-id-gh-infra"
      subject = "${local.github_repo}:environment:${var.github_environment_infra}"
    }
    app = {
      name    = "${local.prefix}-id-gh-app"
      subject = "${local.github_repo}:environment:${var.github_environment_app}"
    }
    pr = {
      name    = "${local.prefix}-id-gh-pr"
      subject = "${local.github_repo}:pull_request"
    }
  }
}

resource "azurerm_user_assigned_identity" "github" {
  for_each = local.pipeline_identities

  name                = each.value.name
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = azurerm_resource_group.bootstrap.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github" {
  for_each = local.pipeline_identities

  name                      = "github-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.github[each.key].id
  audience                  = local.github_audience
  issuer                    = local.github_issuer
  subject                   = each.value.subject
}

# ---------- id-gh-infra: applies the main configuration ----------

resource "azurerm_role_assignment" "infra_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github["infra"].principal_id
}

# Contributor cannot write policy assignments or exemptions
# (Microsoft.Authorization/*/write is excluded), so add this.
resource "azurerm_role_assignment" "infra_policy" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Resource Policy Contributor"
  principal_id         = azurerm_user_assigned_identity.github["infra"].principal_id
}

# The infra pipeline must create role assignments (including the deliberate
# W3 Contributor grant to the Mongo VM). The condition limits it to the roles
# in var.assignable_roles, so it can never grant Owner, User Access
# Administrator or RBAC Administrator.
data "azurerm_role_definition" "assignable" {
  for_each = toset(var.assignable_roles)

  name  = each.value
  scope = data.azurerm_subscription.current.id
}

# Custom role for `az aks command invoke` (app deploys). The only built-in
# role with runCommand is the AKS Cluster Admin Role, which also lists the
# cluster admin credential and lacks commandResults/read. Commands run as
# the caller, so Kubernetes RBAC still limits what they can do.
resource "azurerm_role_definition" "aks_command_invoke" {
  name        = var.aks_command_invoke_role_name
  scope       = data.azurerm_subscription.current.id
  description = "Run az aks command invoke on AKS clusters. Commands run as the caller, so Kubernetes RBAC still applies."

  permissions {
    actions = [
      "Microsoft.ContainerService/managedClusters/read",
      "Microsoft.ContainerService/managedClusters/runCommand/action",
      "Microsoft.ContainerService/managedClusters/commandResults/read",
    ]
  }

  assignable_scopes = [data.azurerm_subscription.current.id]
}

# Custom role for the two CRDs the app pipeline deploys. AKS RBAC Writer
# covers core resources only (Deployments, Services and so on), not custom
# resources, so this adds exactly the HTTPRoute and SecretProviderClass the
# tasky manifests contain. infra/ assigns it on the tasky namespace only.
resource "azurerm_role_definition" "aks_tasky_crds" {
  name        = var.aks_tasky_crds_role_name
  scope       = data.azurerm_subscription.current.id
  description = "Manage HTTPRoutes and SecretProviderClasses through Azure RBAC for Kubernetes. Assign at namespace scope."

  permissions {
    data_actions = [
      "Microsoft.ContainerService/managedClusters/gateway.networking.k8s.io/httproutes/read",
      "Microsoft.ContainerService/managedClusters/gateway.networking.k8s.io/httproutes/write",
      "Microsoft.ContainerService/managedClusters/gateway.networking.k8s.io/httproutes/delete",
      "Microsoft.ContainerService/managedClusters/secrets-store.csi.x-k8s.io/secretproviderclasses/read",
      "Microsoft.ContainerService/managedClusters/secrets-store.csi.x-k8s.io/secretproviderclasses/write",
      "Microsoft.ContainerService/managedClusters/secrets-store.csi.x-k8s.io/secretproviderclasses/delete",
    ]
  }

  assignable_scopes = [data.azurerm_subscription.current.id]
}

locals {
  assignable_role_guids = join(", ", concat(
    [for r in data.azurerm_role_definition.assignable : basename(r.id)],
    [
      azurerm_role_definition.aks_command_invoke.role_definition_id,
      azurerm_role_definition.aks_tasky_crds.role_definition_id,
    ],
  ))

  rbac_condition = <<-EOT
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
      )
      OR
      (
        @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.assignable_role_guids}}
      )
    )
    AND
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
      )
      OR
      (
        @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.assignable_role_guids}}
      )
    )
  EOT
}

resource "azurerm_role_assignment" "infra_rbac_admin" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.github["infra"].principal_id
  condition            = local.rbac_condition
  condition_version    = "2.0"
}

resource "azurerm_role_assignment" "infra_tfstate" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github["infra"].principal_id
}

# ---------- id-gh-pr: read-only plan on pull requests ----------

resource "azurerm_role_assignment" "pr_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.github["pr"].principal_id
}

# Plan reads state and takes a lease (lock) on the state blob, which needs
# data-plane write on the state container only.
resource "azurerm_role_assignment" "pr_tfstate" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github["pr"].principal_id
}
