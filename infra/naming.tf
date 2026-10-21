# One naming convention and one tag set for every resource.
# Same prefix as infra/bootstrap, so everything sorts together in the portal.

locals {
  prefix         = "wiz-ex-${var.location_short}"
  prefix_compact = replace(local.prefix, "-", "")

  names = {
    rg      = "${local.prefix}-rg"
    vnet    = "${local.prefix}-vnet"
    aks     = "${local.prefix}-aks"
    vm      = "${local.prefix}-mongo-vm"
    law     = "${local.prefix}-law"
    acr     = "${local.prefix_compact}acr${random_string.suffix.result}"
    storage = "${local.prefix_compact}bkp${random_string.suffix.result}"
  }

  tags = {
    Project     = "wiz-exercise"
    Environment = "exercise"
    Owner       = var.owner_tag
    ManagedBy   = "terraform"
    Repo        = "github.com/${var.github_repository}"
  }
}

# Suffix for names that must be globally unique (ACR, storage)
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}
