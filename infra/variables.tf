variable "subscription_id" {
  description = "Azure subscription ID provided by CloudLabs."
  type        = string
}

variable "location" {
  description = "Azure region, e.g. eastus. Must match the bootstrap."
  type        = string
}

variable "location_short" {
  description = "Short region code used in names, e.g. eus. Must match the bootstrap."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.location_short))
    error_message = "location_short must be 2 to 6 lowercase letters or digits."
  }
}

variable "owner_tag" {
  description = "Value for the Owner tag."
  type        = string
}

variable "github_repository" {
  description = "owner/repo, used in the Repo tag."
  type        = string
  default     = "FonduemangVI/tech-exercise"
}

variable "log_retention_days" {
  description = "Log Analytics retention. 30 days is included in the base price."
  type        = number
  default     = 30
}

variable "law_daily_quota_gb" {
  description = "Daily ingestion cap for Log Analytics, to control cost. Data above the cap is dropped until the next day."
  type        = number
  default     = 1
}

variable "admin_object_id" {
  description = "Entra ID object ID of the administrator (bootstrap output admin_object_id)."
  type        = string
}

variable "admin_ip_cidrs" {
  description = "Public IPs allowed through the Key Vault firewall (and later the AKS API server), in CIDR form. Set as a GitHub secret so it stays out of public run logs."
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.admin_ip_cidrs) > 0 && alltrue([for c in var.admin_ip_cidrs : can(cidrhost(c, 0))])
    error_message = "admin_ip_cidrs must hold at least one valid CIDR, e.g. 203.0.113.10/32."
  }
}

variable "vm_ssh_public_key" {
  description = "SSH public key for the Mongo VM admin user. Not a secret; password login is disabled."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) ", var.vm_ssh_public_key))
    error_message = "vm_ssh_public_key must be an OpenSSH public key."
  }
}

variable "vm_admin_username" {
  description = "Admin user on the Mongo VM."
  type        = string
  default     = "azureuser"
}

variable "vm_size" {
  description = "Mongo VM size. B2s (2 vCPU) is enough for a small MongoDB and keeps cost down."
  type        = string
  default     = "Standard_B2s"
}

variable "vm_image" {
  description = "W1: deliberately outdated OS image (Ubuntu 20.04, standard support ended May 2025)."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}

variable "mongo_version" {
  description = "W2: deliberately outdated MongoDB release series (6.0, end of life 31 Jul 2025)."
  type        = string
  default     = "6.0"
}

variable "aks_node_size" {
  description = "AKS node size. Two 2 vCPU nodes run the platform and the app."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "kubernetes_version" {
  description = "AKS version. null uses the region's default GA version at creation."
  type        = string
  default     = null
}

variable "aks_command_invoke_role_name" {
  description = "Custom role created by infra/bootstrap for az aks command invoke."
  type        = string
  default     = "AKS Command Invoke (tech-exercise)"
}

variable "aks_tasky_crds_role_name" {
  description = "Custom role created by infra/bootstrap for custom resources in tasky (HTTPRoute, SecretProviderClass)."
  type        = string
  default     = "AKS Tasky CRDs (tech-exercise)"
}

variable "github_pr_principal_id" {
  description = "Object ID of id-gh-pr (bootstrap output github_principal_ids.pr). Gets AcrPull for PR image builds."
  type        = string
}

variable "github_app_principal_id" {
  description = "Object ID of id-gh-app (bootstrap output github_principal_ids.app). Gets AcrPush and namespace-scoped AKS access."
  type        = string
}

variable "policy_allowed_images_effect" {
  description = "Effect of the ACR-only images policy (R27). Start with Audit, list every running image, then switch to Deny."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.policy_allowed_images_effect)
    error_message = "policy_allowed_images_effect must be Audit, Deny or Disabled."
  }
}
