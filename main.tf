terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "mtc_rg" {
  name     = "mtc_resources"
  location = "West US 2"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "mtc_vn" {
  name                = "mtc_network"
  resource_group_name = azurerm_resource_group.mtc_rg.name
  location            = azurerm_resource_group.mtc_rg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "mtc_subnet" {
  name                 = "mtc_subnet"
  resource_group_name  = azurerm_resource_group.mtc_rg.name
  virtual_network_name = azurerm_virtual_network.mtc_vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "mtc_nsg" {
  name                = "mtc_nsg"
  resource_group_name = azurerm_resource_group.mtc_rg.name
  location            = azurerm_resource_group.mtc_rg.location

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "mtc_dev_rule" {
  name                        = "mtc_dev_rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.mtc_rg.name
  network_security_group_name = azurerm_network_security_group.mtc_nsg.name
}

resource "azurerm_subnet_network_security_group_association" "mtc_nsga" {
  subnet_id                 = azurerm_subnet.mtc_subnet.id
  network_security_group_id = azurerm_network_security_group.mtc_nsg.id
}

resource "azurerm_public_ip" "mtc_ip" {
  name                = "mtc_ip"
  allocation_method   = "Static"
  resource_group_name = azurerm_resource_group.mtc_rg.name
  location            = azurerm_resource_group.mtc_rg.location
  zones               = ["2"]
  sku                 = "Standard"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "mtc_nic" {
  name                = "mtc_nic"
  location            = azurerm_resource_group.mtc_rg.location
  resource_group_name = azurerm_resource_group.mtc_rg.name

  ip_configuration {
    name                          = "internal"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.mtc_subnet.id
    public_ip_address_id          = azurerm_public_ip.mtc_ip.id
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_virtual_machine" "mtc_vm" {
  name                  = "mtc-vm"
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  location              = azurerm_resource_group.mtc_rg.location
  resource_group_name   = azurerm_resource_group.mtc_rg.name
  network_interface_ids = [azurerm_network_interface.mtc_nic.id]
  zone                  = "2"

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/mtcazurekey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("linux-ssh-script.tpl", {
      hostname     = self.public_ip_address
      user         = "adminuser"
      identityfile = "~/.ssh/mtcazurekey"
    })
    interpreter = ["bash", "-c"]
  }

  tags = {
    environment = "dev"
  }
}
