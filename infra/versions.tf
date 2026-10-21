terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Partial backend configuration. The storage account details come from
  # -backend-config in the pipeline (repo variables) or from backend.hcl
  # locally. Access is Entra ID only: the state account has shared keys off.
  backend "azurerm" {
    key              = "infra.tfstate"
    use_azuread_auth = true
  }
}
