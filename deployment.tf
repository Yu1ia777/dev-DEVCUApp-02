provider "azurerm" {
  features {}
  subscription_id = "5de01a72-71aa-4798-b8b9-499e15785cdc"
}

# VARIABLE VM 
variable "vm" {
  description = "Name Terraform Linux VM"
  type        = string
  default     = "TOOLSYUL000" 
}

#RG NETWORK
resource "azurerm_resource_group" "rg1" {
  name     = "rg-yulnetwork-dev-00"
  location = "West Europe"
}

#RG APPLICATION
resource "azurerm_resource_group" "rg2" {
  name     = "rg-yulapplication-dev-00"
  location = "West Europe"
}

# PIP
resource "azurerm_public_ip" "pip" {
  name                = "pip-dev-${var.vm}-00-westeurope"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name
  allocation_method   = "Static"
  sku                 = "Standard" # Recomendado para IPs estáticas

}

#VARIABLE IP LOCAL
locals {
  variable_ip = azurerm_network_interface.nic.private_ip_address
}

#NSG 
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-vnet-10-249-10-0-24-westeurope"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name

  # Allow SSH (port 22) inbound
  security_rule {
    name                       = "Allow_SSH_to_${local.variable_ip}_Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*" 
    destination_address_prefix = azurerm_network_interface.nic.private_ip_address #Referencia ip privada
  }
  # Allow RDP (port 3389) inbound
  security_rule {
    name                       = "Allow_RDP_to_${local.variable_ip}_Inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = azurerm_network_interface.nic.private_ip_address
  }
}

#VNET
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-10-249-10-0-24-westeurope"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name
  address_space       = ["10.249.10.0/24"]

}

#SNET
resource "azurerm_subnet" "snet" {
  name                 = "snet-10-249-10-0-24-vm"
  resource_group_name  = azurerm_resource_group.rg1.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.249.10.0/24"]
}

 # Associate the NSG with the SUBNET
resource "azurerm_subnet_network_security_group_association" "nsg-association" {
  subnet_id                 = azurerm_subnet.snet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# NIC
resource "azurerm_network_interface" "nic" {
  name                = "nic-YUL-10-249-10-0-24"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.snet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# TOOLS VM
resource "azurerm_linux_virtual_machine" "vm1" {
  name                  = "vm-${var.vm}" 
  resource_group_name   = azurerm_resource_group.rg2.name
  location              = azurerm_resource_group.rg2.location
  size                  = "Standard_B1s"
  admin_username        = "admi"
  admin_password        = "Admin123*" 
  network_interface_ids = [azurerm_network_interface.nic.id]

os_disk {
    name                   = "disk-${var.vm}-DataDisk00"
    caching                = "ReadWrite"
    storage_account_type   = "Standard_LRS"
    disk_size_gb           = 30
    write_accelerator_enabled = false
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  disable_password_authentication = false
}

# Extensión para instalar PowerShell, Azure CLI y Terraform
resource "azurerm_virtual_machine_extension" "custom_script" {
  name                 = "install-tools"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm1.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
    {
      "commandToExecute": "sudo apt-get update -y && sudo apt-get upgrade -y && wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb && sudo dpkg -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb && sudo apt-get update -y && sudo apt-get install -y powershell && curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash && wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && echo 'deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com jammy main' | sudo tee /etc/apt/sources.list.d/hashicorp.list && sudo apt-get update -y && sudo apt-get install -y terraform && sudo apt-get autoremove -y && sudo apt-get clean"
    }
  SETTINGS
}