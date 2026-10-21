output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "mongo_public_ip" {
  description = "For SSH (W4): ssh -i ~/.ssh/wiz-exercise azureuser@<ip>"
  value       = azurerm_public_ip.mongo.ip_address
}

output "mongo_private_ip" {
  value = local.mongo_private_ip
}

output "backup_list_url" {
  description = "W6: anonymous listing of the backups container"
  value       = "https://${azurerm_storage_account.backup.name}.blob.core.windows.net/${azurerm_storage_container.backups.name}?restype=container&comp=list"
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "aks_oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "workload_identity_client_ids" {
  description = "Client IDs for the service account annotations (azure.workload.identity/client-id). Not secrets."
  value = {
    flux  = azurerm_user_assigned_identity.flux.client_id
    tasky = azurerm_user_assigned_identity.tasky.client_id
  }
}
