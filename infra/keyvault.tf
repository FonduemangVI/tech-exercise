# Key Vault for every secret the environment needs (Mongo URIs, JWT secret).
#
# No private endpoint, so the public endpoint is locked down instead:
# - Azure RBAC only (no access policies), data plane roles per identity
# - firewall default Deny; only the admin IP and the AKS and DB subnets
#   (through Microsoft.KeyVault service endpoints) reach the data plane
# - purge protection, so a deleted vault or secret can be recovered
# - AuditEvent logs to Log Analytics (diagnostics.tf)
#
# Terraform never writes secret values. The Mongo VM generates its own
# credentials at first boot and writes them here with its managed identity,
# so no secret reaches Terraform state, VM custom data or pipeline logs.
# Accepted as OPS-2 in docs/risk-register.md.

data "azurerm_client_config" "current" {}

locals {
  # Key Vault rejects /31 and /32 prefixes: single addresses go in bare.
  kv_ip_rules = [for c in var.admin_ip_cidrs : trimsuffix(c, "/32")]

  # Filled in by the network change: snet-aks and snet-db, each with the
  # Microsoft.KeyVault service endpoint. Until then only the admin IP and
  # trusted Azure services get through.
  kv_subnet_ids = []
}

resource "azurerm_key_vault" "main" {
  name                = local.names.kv
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = true # OPS-2: no private endpoint; firewall below

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    ip_rules                   = local.kv_ip_rules
    virtual_network_subnet_ids = local.kv_subnet_ids
  }

  tags = local.tags
}

# Admin sees vault and secret metadata, not values. Reading a value means a
# deliberate, logged role change (break glass).
resource "azurerm_role_assignment" "admin_kv_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Reader"
  principal_id         = var.admin_object_id
}

# Added with the parts that use them:
# - Mongo VM identity: Key Vault Secrets Officer (writes its credentials)
# - id-tasky (AKS workload identity): Key Vault Secrets User
