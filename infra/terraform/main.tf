data "azurerm_resource_group" "phoenix" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "phoenix" {
  name                = "vnet-phoenix"
  resource_group_name = data.azurerm_resource_group.phoenix.name
}

data "azurerm_subnet" "control" {
  name                 = "control-subnet"
  virtual_network_name = data.azurerm_virtual_network.phoenix.name
  resource_group_name  = data.azurerm_resource_group.phoenix.name
}

resource "azurerm_public_ip" "worker" {
  count               = var.worker_count
  name                = "${var.project_name}-worker-${count.index + 1}-pip"
  location            = data.azurerm_resource_group.phoenix.location
  resource_group_name = data.azurerm_resource_group.phoenix.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "workers" {
  name                = "${var.project_name}-workers-nsg"
  location            = data.azurerm_resource_group.phoenix.location
  resource_group_name = data.azurerm_resource_group.phoenix.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-K3s-API"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-Flannel"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "8472"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "worker" {
  count               = var.worker_count
  name                = "${var.project_name}-worker-${count.index + 1}-nic"
  location            = data.azurerm_resource_group.phoenix.location
  resource_group_name = data.azurerm_resource_group.phoenix.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.control.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.worker[count.index].id
  }
}

resource "azurerm_network_interface_security_group_association" "worker" {
  count                     = var.worker_count
  network_interface_id      = azurerm_network_interface.worker[count.index].id
  network_security_group_id = azurerm_network_security_group.workers.id
}

resource "azurerm_linux_virtual_machine" "worker" {
  count               = var.worker_count
  name                = "${var.project_name}-worker-${count.index + 1}"
  location            = data.azurerm_resource_group.phoenix.location
  resource_group_name = data.azurerm_resource_group.phoenix.name
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.worker[count.index].id
  ]

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}
