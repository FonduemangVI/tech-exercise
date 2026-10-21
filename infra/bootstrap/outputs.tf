output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_subscription.current.subscription_id
}

output "github_client_ids" {
  description = "Client IDs for azure/login in each pipeline job. Not secrets."
  value       = { for k, v in azurerm_user_assigned_identity.github : k => v.client_id }
}

output "github_principal_ids" {
  description = "Object IDs, used by infra/ to grant ACR and AKS roles."
  value       = { for k, v in azurerm_user_assigned_identity.github : k => v.principal_id }
}

output "tfstate" {
  description = "Values for the azurerm backend in infra/."
  value = {
    resource_group_name  = azurerm_resource_group.bootstrap.name
    storage_account_name = azurerm_storage_account.tfstate.name
    container_name       = azurerm_storage_container.tfstate.name
  }
}

output "location" {
  description = "Region and short code, reused by infra/ so names match."
  value = {
    name  = var.location
    short = var.location_short
  }
}

output "owner_tag" {
  value = var.owner_tag
}

output "github_environments" {
  value = {
    infra = var.github_environment_infra
    app   = var.github_environment_app
  }
}

output "admin_object_id" {
  description = "Object ID of whoever ran the bootstrap. infra/ grants this person read access to resources such as Key Vault metadata."
  value       = data.azurerm_client_config.current.object_id
}
