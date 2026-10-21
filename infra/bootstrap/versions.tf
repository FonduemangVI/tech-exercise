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

  # Bootstrap state stays local on purpose: this configuration creates the
  # remote state storage that everything else uses. The local state file is
  # git-ignored and must not be committed.
}
