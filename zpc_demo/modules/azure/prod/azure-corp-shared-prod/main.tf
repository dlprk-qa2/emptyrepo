provider "azurerm" {
  alias           = "corp-shared-prod"
  subscription_id = "${var.subscription}"
  features {}
}


##### Variables for the entire subscription: 

variable "environment" {
  default = "prod"
}

variable "region" {
  default = "westus"
}

variable "subscription" {
}

##### Data: 

data "azurerm_subscription" "corp-shared-prod" {
}



##### hr application resources: 


resource "azurerm_container_registry" "cr-hr" {
  provider = azurerm.corp-shared-prod 
  name                = "crhr${var.environment}${var.region}"
  resource_group_name = azurerm_resource_group.rg-hr.name
  location            = azurerm_resource_group.rg-hr.location
  sku                 = "Premium"
  admin_enabled       = false
  georeplications {
    location                = "East US"
    zone_redundancy_enabled = true
    tags                    = {}
  }
  georeplications {
    location                = "westeurope"
    zone_redundancy_enabled = true
    tags                    = {}
  }
}




resource "azurerm_role_assignment" "roleassingment-hr" {
  provider = azurerm.corp-shared-prod 
  scope                = data.azurerm_subscription.corp-shared-prod.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.hr-server-identity.principal_id
}


resource "azurerm_user_assigned_identity" "hr-server-identity" {
  provider = azurerm.corp-shared-prod 
  resource_group_name   = azurerm_resource_group.rg-hr.name
  location = "${var.region}"
  name = "hr-server-identity"
}



resource "azurerm_resource_group" "rg-hr" {
  provider = azurerm.corp-shared-prod 
  name     = "rg-hr-${var.environment}"
  location = "${var.region}"
}



resource "azurerm_mysql_server" "mysql-hr" {
  provider = azurerm.corp-shared-prod 
  name                = "mysql-hr-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-hr.location
  resource_group_name = azurerm_resource_group.rg-hr.name

  administrator_login          = "mysqladminun"
  administrator_login_password = "H@Sh1CoR3!"

  sku_name   = "B_Gen5_2"
  storage_mb = 5120
  version    = "5.7"

  auto_grow_enabled                 = true
  backup_retention_days             = 7
  geo_redundant_backup_enabled      = false
  infrastructure_encryption_enabled = false
  public_network_access_enabled     = true
  ssl_enforcement_enabled           = true
  ssl_minimal_tls_version_enforced  = "TLS1_2"
}


resource "azurerm_storage_account" "st-hr" {
  provider = azurerm.corp-shared-prod 
  name                     = "sthr${var.environment}${var.region}"
  resource_group_name      = azurerm_resource_group.rg-hr.name
  location                 = azurerm_resource_group.rg-hr.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "plan-hr" {
  provider = azurerm.corp-shared-prod 
  name                = "plan-hr-${var.environment}-${var.region}"
  resource_group_name = azurerm_resource_group.rg-hr.name
  location            = azurerm_resource_group.rg-hr.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "func-hr" {
  provider = azurerm.corp-shared-prod 
  name                = "func-hr-${var.environment}-${var.region}"
  resource_group_name = azurerm_resource_group.rg-hr.name
  location            = azurerm_resource_group.rg-hr.location

  storage_account_name = azurerm_storage_account.st-hr.name
  service_plan_id      = azurerm_service_plan.plan-hr.id

  site_config {}
}


resource "azurerm_virtual_network" "vnet-hr" {
  provider = azurerm.corp-shared-prod 
  name                = "vnet-hr-${var.environment}-${var.region}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg-hr.location
  resource_group_name = azurerm_resource_group.rg-hr.name
}



resource "azurerm_subnet" "snet-hr" {
  provider = azurerm.corp-shared-prod 
  name                 = "snet-hr-${var.environment}-${var.region}"
  resource_group_name  = azurerm_resource_group.rg-hr.name
  virtual_network_name = azurerm_virtual_network.vnet-hr.name
  address_prefixes     = ["10.0.2.0/24"]
}



resource "azurerm_network_interface" "nic-hr-vm1" {
  provider = azurerm.corp-shared-prod 
  name                = "nic-hr-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-hr.location
  resource_group_name = azurerm_resource_group.rg-hr.name

  ip_configuration {
    name                          = "hr-ip"
    subnet_id                     = azurerm_subnet.snet-hr.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.pip-hr.id 
  }
}


resource "azurerm_network_security_group" "nsg-hr-vm1" {
  provider = azurerm.corp-shared-prod 
  name                = "nsg-hr-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-hr.location
  resource_group_name = azurerm_resource_group.rg-hr.name

  security_rule {
    name                       = "remote-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "${var.environment}"
  }
}


resource "azurerm_network_interface_security_group_association" "nsg-association-hr-vm1" {
  provider = azurerm.corp-shared-prod 
  network_interface_id      = azurerm_network_interface.nic-hr-vm1.id
  network_security_group_id = azurerm_network_security_group.nsg-hr-vm1.id
}


resource "azurerm_linux_virtual_machine" "vm-hr-1" {
  provider = azurerm.corp-shared-prod 
  name                  = "vm-hr-${var.environment}-${var.region}-1"
  location              = azurerm_resource_group.rg-hr.location
  resource_group_name   = azurerm_resource_group.rg-hr.name
  network_interface_ids = [azurerm_network_interface.nic-hr-vm1.id]
  size               = "Standard_A1_v2"


source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  
  
  os_disk {
    name                 = "osdisk-hr"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }


  computer_name                   = "hr-vm"
  admin_username                  = "azureuser"
  disable_password_authentication = true

    admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.tls-hr.public_key_openssh
  }


}



resource "tls_private_key" "tls-hr" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_public_ip" "pip-hr" {
  provider = azurerm.corp-shared-prod 
  name                = "pip-hr-${var.environment}-${var.region}"
  resource_group_name = azurerm_resource_group.rg-hr.name
  location            = azurerm_resource_group.rg-hr.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "${var.environment}"
  }
}

resource "azurerm_kubernetes_cluster" "aks-hr" {
  provider = azurerm.corp-shared-prod 
  name                = "aks-hr-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-hr.location
  resource_group_name = azurerm_resource_group.rg-hr.name
  dns_prefix          = "safemarch-aks-hr"


  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.hr-server-identity.id]
  }



  tags = {
    Environment = "${var.environment}"
  }
}


##### crm application resources:




resource "azurerm_container_registry" "cr-crm" {
  provider = azurerm.corp-shared-prod 
  name                = "crcrm${var.environment}${var.region}"
  resource_group_name = azurerm_resource_group.rg-crm.name
  location            = azurerm_resource_group.rg-crm.location
  sku                 = "Premium"
  admin_enabled       = false
  georeplications {
    location                = "East US"
    zone_redundancy_enabled = true
    tags                    = {}
  }
  georeplications {
    location                = "westeurope"
    zone_redundancy_enabled = true
    tags                    = {}
  }
}





resource "azurerm_role_assignment" "roleassingment-crm" {
  provider = azurerm.corp-shared-prod 
  scope                = data.azurerm_subscription.corp-shared-prod.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.crm-server-identity.principal_id
}


resource "azurerm_user_assigned_identity" "crm-server-identity" {
  provider = azurerm.corp-shared-prod 
  resource_group_name   = azurerm_resource_group.rg-crm.name
  location = "${var.region}"
  name = "crm-server-identity"
}



resource "azurerm_resource_group" "rg-crm" {
  provider = azurerm.corp-shared-prod 
  name     = "rg-crm-${var.environment}"
  location = "${var.region}"
}



resource "azurerm_mysql_server" "mysql-crm" {
  provider = azurerm.corp-shared-prod 
  name                = "mysql-crm-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-crm.location
  resource_group_name = azurerm_resource_group.rg-crm.name

  administrator_login          = "mysqladminun"
  administrator_login_password = "H@Sh1CoR3!"

  sku_name   = "B_Gen5_2"
  storage_mb = 5120
  version    = "5.7"

  auto_grow_enabled                 = true
  backup_retention_days             = 7
  geo_redundant_backup_enabled      = false
  infrastructure_encryption_enabled = false
  public_network_access_enabled     = true
  ssl_enforcement_enabled           = true
  ssl_minimal_tls_version_enforced  = "TLS1_2"
}


resource "azurerm_storage_account" "st-crm" {
  provider = azurerm.corp-shared-prod 
  name                     = "stcrm${var.environment}${var.region}"
  resource_group_name      = azurerm_resource_group.rg-crm.name
  location                 = azurerm_resource_group.rg-crm.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "plan-crm" {
  provider = azurerm.corp-shared-prod 
  name                = "plan-crm-${var.environment}-${var.region}"
  resource_group_name = azurerm_resource_group.rg-crm.name
  location            = azurerm_resource_group.rg-crm.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "func-crm" {
  provider = azurerm.corp-shared-prod 
  name                = "func-crm-${var.environment}-${var.region}"
  resource_group_name = azurerm_resource_group.rg-crm.name
  location            = azurerm_resource_group.rg-crm.location

  storage_account_name = azurerm_storage_account.st-crm.name
  service_plan_id      = azurerm_service_plan.plan-crm.id

  site_config {}
}


resource "azurerm_virtual_network" "vnet-crm" {
  provider = azurerm.corp-shared-prod 
  name                = "vnet-crm-${var.environment}-${var.region}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg-crm.location
  resource_group_name = azurerm_resource_group.rg-crm.name
}



resource "azurerm_subnet" "snet-crm" {
  provider = azurerm.corp-shared-prod 
  name                 = "snet-crm-${var.environment}-${var.region}"
  resource_group_name  = azurerm_resource_group.rg-crm.name
  virtual_network_name = azurerm_virtual_network.vnet-crm.name
  address_prefixes     = ["10.0.2.0/24"]
}



resource "azurerm_network_interface" "nic-crm-vm1" {
  provider = azurerm.corp-shared-prod 
  name                = "nic-crm-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-crm.location
  resource_group_name = azurerm_resource_group.rg-crm.name

  ip_configuration {
    name                          = "crm-ip"
    subnet_id                     = azurerm_subnet.snet-crm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.pip-crm.id 
  }
}


resource "azurerm_network_security_group" "nsg-crm-vm1" {
  provider = azurerm.corp-shared-prod 
  name                = "nsg-crm-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-crm.location
  resource_group_name = azurerm_resource_group.rg-crm.name

  security_rule {
    name                       = "remote-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "${var.environment}"
  }
}


resource "azurerm_network_interface_security_group_association" "nsg-association-crm-vm1" {
  provider = azurerm.corp-shared-prod 
  network_interface_id      = azurerm_network_interface.nic-crm-vm1.id
  network_security_group_id = azurerm_network_security_group.nsg-crm-vm1.id
}


resource "azurerm_linux_virtual_machine" "vm-crm-1" {
  provider = azurerm.corp-shared-prod 
  name                  = "vm-crm-${var.environment}-${var.region}-1"
  location              = azurerm_resource_group.rg-crm.location
  resource_group_name   = azurerm_resource_group.rg-crm.name
  network_interface_ids = [azurerm_network_interface.nic-crm-vm1.id]
  size               = "Standard_A1_v2"


source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  
  
  os_disk {
    name                 = "osdisk-crm"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }


  computer_name                   = "crm-vm"
  admin_username                  = "azureuser"
  disable_password_authentication = true

    admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.tls-crm.public_key_openssh
  }


}



resource "tls_private_key" "tls-crm" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_public_ip" "pip-crm" {
  provider = azurerm.corp-shared-prod 
  name                = "pip-crm-${var.environment}-${var.region}"
  resource_group_name = azurerm_resource_group.rg-crm.name
  location            = azurerm_resource_group.rg-crm.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "${var.environment}"
  }
}

resource "azurerm_kubernetes_cluster" "aks-crm" {
  provider = azurerm.corp-shared-prod 
  name                = "aks-crm-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-crm.location
  resource_group_name = azurerm_resource_group.rg-crm.name
  dns_prefix          = "safemarch-aks-crm"


  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.crm-server-identity.id]
  }



  tags = {
    Environment = "${var.environment}"
  }
}






