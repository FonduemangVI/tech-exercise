# R27 preventative control: only images from this ACR may run in the
# cluster. Built-in definition "Kubernetes cluster containers should only
# use allowed images", enforced by the Azure Policy add-on (Gatekeeper).
#
# Rollout: Audit first, list every running image (demo.sh), then set
# policy_allowed_images_effect = "Deny".
#
# This does not remove W5: it stops unknown images, but cluster-admin still
# works. Admission control and RBAC are separate layers.

locals {
  allowed_images_regex = "^${replace(azurerm_container_registry.main.login_server, ".", "\\.")}/.+$"

  # The built-in defaults, plus aks-command: az aks command invoke runs its
  # pod there from an MCR image, and app.yml deploys through it.
  policy_excluded_namespaces = [
    "kube-system",
    "gatekeeper-system",
    "azure-arc",
    "azure-extensions-usage-system",
    "aks-command",
  ]
}

resource "azurerm_resource_policy_assignment" "aks_allowed_images" {
  name                 = "acr-only-images"
  display_name         = "AKS: only images from ${azurerm_container_registry.main.name}"
  resource_id          = azurerm_kubernetes_cluster.main.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/febd0533-8e55-448f-b837-bd0e06f16469"

  parameters = jsonencode({
    effect                      = { value = var.policy_allowed_images_effect }
    allowedContainerImagesRegex = { value = local.allowed_images_regex }
    excludedNamespaces          = { value = local.policy_excluded_namespaces }
  })
}
