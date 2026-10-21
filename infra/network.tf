# One VNet, three subnets, an NSG per workload subnet.
#
# All subnets are Azure "private subnets" (default_outbound_access_enabled =
# false): nothing gets implicit internet egress. AKS nodes egress through the
# cluster load balancer's outbound rules; the Mongo VM through its public IP.
#
# Overlay CNI: pod traffic leaves with the node IP, so rules that mean "from
# the cluster" use the node subnet as the source.

locals {
  vnet_cidr = "10.10.0.0/16"

  subnets = {
    aks       = "10.10.0.0/22" # AKS nodes (pods use the overlay range, not VNet IPs)
    apiserver = "10.10.4.0/28" # AKS API server VNet Integration, delegated
    db        = "10.10.8.0/24" # Mongo VM
  }
}

resource "azurerm_virtual_network" "main" {
  name                = local.names.vnet
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [local.vnet_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "aks" {
  name                            = "snet-aks"
  resource_group_name             = azurerm_resource_group.main.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = [local.subnets.aks]
  default_outbound_access_enabled = false

  # tasky secrets via the CSI driver
  service_endpoint {
    service = "Microsoft.KeyVault"
  }
}

# Holds the API server's internal load balancer. AKS manages this subnet;
# no NSG, so node to API server traffic is never blocked by mistake.
resource "azurerm_subnet" "apiserver" {
  name                            = "snet-apiserver"
  resource_group_name             = azurerm_resource_group.main.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = [local.subnets.apiserver]
  default_outbound_access_enabled = false

  delegation {
    name = "aks-apiserver"
    service_delegation {
      name = "Microsoft.ContainerService/managedClusters"
    }
  }
}

resource "azurerm_subnet" "db" {
  name                            = "snet-db"
  resource_group_name             = azurerm_resource_group.main.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = [local.subnets.db]
  default_outbound_access_enabled = false

  # VM writes and reads its credentials
  service_endpoint {
    service = "Microsoft.KeyVault"
  }
}

# ---------------------------------------------------------------------------
# NSG: snet-db (Mongo VM)
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "db" {
  name                = "${local.prefix}-nsg-db"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db.id
}

# W4 (R8): SSH open to the internet. Intentional, required by the brief.
# See docs/issue-register.md.
#trivy:ignore:AZU-0047
#trivy:ignore:AZU-0050
resource "azurerm_network_security_rule" "db_ssh_internet" {
  name                        = "allow-ssh-internet-W4"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "Internet"
  destination_address_prefix  = local.subnets.db
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.db.name
}

# R11: Mongo reachable only from the AKS node subnet
resource "azurerm_network_security_rule" "db_mongo_from_aks" {
  name                        = "allow-mongo-from-aks"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "27017"
  source_address_prefix       = local.subnets.aks
  destination_address_prefix  = local.subnets.db
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.db.name
}

# The default AllowVnetInBound rule would let every subnet reach Mongo
# (including snet-apiserver). Deny anything not matched above.
resource "azurerm_network_security_rule" "db_mongo_deny_other" {
  name                        = "deny-mongo-other"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "27017"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.db.name
}

# ---------------------------------------------------------------------------
# NSG: snet-aks (nodes). Nodes have no public IPs; the only internet
# entry is the Envoy Gateway load balancer.
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "aks" {
  name                = "${local.prefix}-nsg-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# R5 and R18: the web app is public by design. 443 serves the app over TLS;
# 80 only redirects to HTTPS and answers Let's Encrypt HTTP-01 challenges.
# Nodes have no public IPs, so this only reaches services behind the
# cluster load balancer.
#trivy:ignore:AZU-0047
resource "azurerm_network_security_rule" "aks_web_internet" {
  name                        = "allow-web-internet"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443"]
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.aks.name
}
