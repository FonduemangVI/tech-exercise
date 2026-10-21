provider "azurerm" {
  features {}

  subscription_id = var.subscription_id

  # azurerm 5.x registers no Azure resource providers by default. The
  # bootstrap runs as the subscription Owner, so it registers everything the
  # environment needs, once. The pipelines then never need register rights
  # (the PR identity is Reader only).
  resource_providers_to_register = [
    "Microsoft.Compute",             # Mongo VM, AKS nodes
    "Microsoft.ContainerRegistry",   # ACR
    "Microsoft.ContainerService",    # AKS
    "Microsoft.Insights",            # diagnostic settings, Activity Log export, log alert
    "Microsoft.KeyVault",            # Key Vault
    "Microsoft.ManagedIdentity",     # pipeline and workload identities, federated credentials
    "Microsoft.Network",             # VNet, NSGs, load balancers, public IPs
    "Microsoft.OperationalInsights", # Log Analytics workspace
    "Microsoft.PolicyInsights",      # Azure Policy add-on for AKS
    "Microsoft.Security",            # Defender for Cloud free-tier recommendations
    "Microsoft.Storage",             # state and backup storage accounts
  ]

  # The state storage account has shared keys disabled, so all data-plane
  # access uses Entra ID.
  storage_use_azuread = true
}
