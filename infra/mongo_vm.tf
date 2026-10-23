# Mongo VM. Carries three of the intentional weaknesses:
#   W1 outdated OS (var.vm_image), W2 outdated MongoDB (var.mongo_version),
#   W3 Contributor on the subscription (below). W4, SSH from the internet,
#   is in network.tf. See docs/issue-register.md.
#
# Everything else is locked down: SSH key only, Trusted Launch, MongoDB
# auth on and bound to the private IP, credentials generated on the VM and
# kept in Key Vault.
#
# Changing anything in infra/vm/ changes custom_data, which replaces the
# VM (new disk, empty database). The bootstrap script then reuses the
# passwords already in Key Vault, so tasky keeps working.

locals {
  mongo_private_ip = cidrhost(local.subnets.db, 10) # 10.10.0.90, fixed so the app URI never changes

  mongo_cloud_init = templatefile("${path.module}/vm/cloud-init.yaml.tftpl", {
    kv_uri           = azurerm_key_vault.main.vault_uri
    storage_account  = azurerm_storage_account.backup.name
    backup_container = azurerm_storage_container.backups.name
    mongo_private_ip = local.mongo_private_ip
    mongo_version    = var.mongo_version
    kv_sh            = filebase64("${path.module}/vm/kv.sh")
    bootstrap_sh     = filebase64("${path.module}/vm/mongo-bootstrap.sh")
    backup_sh        = filebase64("${path.module}/vm/mongo-backup.sh")
  })
}

resource "azurerm_public_ip" "mongo" {
  name                = "${local.names.vm}-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "mongo" {
  name                = "${local.names.vm}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.db.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.mongo_private_ip
    public_ip_address_id          = azurerm_public_ip.mongo.id
  }
}

resource "azurerm_linux_virtual_machine" "mongo" {
  name                  = local.names.vm
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = var.vm_size
  network_interface_ids = [azurerm_network_interface.mongo.id]

  admin_username                  = var.vm_admin_username
  disable_password_authentication = true # also ssh_pwauth: false in cloud-init

  # Temp disk and cache encrypted on the host as well (Defender). Needs the
  # Microsoft.Compute/EncryptionAtHost feature; turning it on deallocates
  # and restarts the VM, the disk and data stay.
  encryption_at_host_enabled = true

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = var.vm_ssh_public_key
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = var.vm_image.publisher
    offer     = var.vm_image.offer
    sku       = var.vm_image.sku
    version   = var.vm_image.version
  }

  # Trusted Launch: free, and blocks boot-level tampering
  secure_boot_enabled = true
  vtpm_enabled        = true

  boot_diagnostics {} # managed storage; serial console for cloud-init debugging

  custom_data = base64encode(local.mongo_cloud_init)

  tags = local.tags
}

# W3: Contributor on the whole subscription. Intentional, required by the
# brief ("overly permissive CSP permissions, e.g. able to create VMs").
resource "azurerm_role_assignment" "mongo_vm_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_virtual_machine.mongo.identity[0].principal_id
}

# What the VM actually needs: write backups, and write and read its own
# credentials. These are the only roles left after W3 is fixed.
resource "azurerm_role_assignment" "mongo_vm_backup_writer" {
  scope                = azurerm_storage_container.backups.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.mongo.identity[0].principal_id
}

resource "azurerm_role_assignment" "mongo_vm_kv_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_linux_virtual_machine.mongo.identity[0].principal_id
}
