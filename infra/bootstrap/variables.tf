variable "subscription_id" {
  description = "Azure subscription ID provided by CloudLabs."
  type        = string
}

variable "location" {
  description = "Azure region, e.g. australiaeast."
  type        = string
}

variable "location_short" {
  description = "Short region code used in names, e.g. auea for australiaeast."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.location_short))
    error_message = "location_short must be 2 to 6 lowercase letters or digits."
  }
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "github_environment_infra" {
  description = "GitHub environment used by the infra apply job."
  type        = string
  default     = "prod-infra"
}

variable "github_environment_app" {
  description = "GitHub environment used by the app deploy job."
  type        = string
  default     = "prod-app"
}

variable "owner_tag" {
  description = "Value for the Owner tag."
  type        = string
}

variable "aks_command_invoke_role_name" {
  description = "Name of the custom role for az aks command invoke. infra/ assigns it by this name."
  type        = string
  default     = "AKS Command Invoke (tech-exercise)"
}

variable "assignable_roles" {
  description = "Built-in roles the infra pipeline identity may assign (the custom command invoke role is added to the condition automatically). Anything else (Owner, User Access Administrator, RBAC Administrator) is blocked by the role assignment condition."
  type        = list(string)
  default = [
    "Contributor",
    "Storage Blob Data Contributor",
    "AcrPull",
    "AcrPush",
    "Network Contributor",
    "Azure Kubernetes Service Cluster User Role",
    "Azure Kubernetes Service RBAC Writer",
    "Azure Kubernetes Service RBAC Cluster Admin",
    "Key Vault Secrets Officer",
    "Key Vault Secrets User",
    "Key Vault Reader",
  ]
}
