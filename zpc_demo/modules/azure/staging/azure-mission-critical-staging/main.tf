provider "azurerm" {
  alias           = "mission-critical-staging"
  subscription_id = "${var.subscription}"
  features {}
}


##### Variables for the entire subscription: 

variable "environment" {
  default = "staging"
}

variable "region" {
  default = "westus"
}

variable "subscription" {
}

##### Data: 

data "azurerm_subscription" "mission-critical-staging" {
}



##### Finance application resources: 


resource "azurerm_container_registry" "cr-finance" {
  provider = azurerm.mission-critical-staging 
  name                = "crFinance${var.environment}${var.region}"
  resource_group_name = azurerm_resource_group.rg-finance.name
  location            = azurerm_resource_group.rg-finance.location
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




resource "azurerm_role_assignment" "roleassingment-finance" {
  provider = azurerm.mission-critical-staging 
  scope                = data.azurerm_subscription.mission-critical-staging.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.finance-server-identity.principal_id
}


resource "azurerm_user_assigned_identity" "finance-server-identity" {
  provider = azurerm.mission-critical-staging 
  resource_group_name   = azurerm_resource_group.rg-finance.name
  location = "${var.region}"
  name = "finance-server-identity"
}



resource "azurerm_resource_group" "rg-finance" {
  provider = azurerm.mission-critical-staging 
  name     = "rg-finance-${var.environment}"
  location = "${var.region}"
}



resource "azurerm_mysql_server" "mysql-finance" {
  provider = azurerm.mission-critical-staging 
  name                = "mysql-finance-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-finance.location
  resource_group_name = azurerm_resource_group.rg-finance.name

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


resource "azurerm_storage_account" "st-finance" {
  provider = azurerm.mission-critical-staging 
  name                     = "stfinance${var.environment}${var.region}"
  resource_group_name      = azurerm_resource_group.rg-finance.name
  location                 = azurerm_resource_group.rg-finance.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "plan-finance" {
  provider = azurerm.mission-critical-staging 
  name                = "plan-finance-${var.environment}-${var.region}"
  resource_group_name = azurerm_resource_group.rg-finance.name
  location            = azurerm_resource_group.rg-finance.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "func-finance" {
  provider = azurerm.mission-critical-staging 
  name                = "func-finance-${var.environment}-${var.region}"
  resource_group_name = azurerm_resource_group.rg-finance.name
  location            = azurerm_resource_group.rg-finance.location

  storage_account_name = azurerm_storage_account.st-finance.name
  service_plan_id      = azurerm_service_plan.plan-finance.id

  site_config {}
}


resource "azurerm_virtual_network" "vnet-finance" {
  provider = azurerm.mission-critical-staging 
  name                = "vnet-finance-${var.environment}-${var.region}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg-finance.location
  resource_group_name = azurerm_resource_group.rg-finance.name
}



resource "azurerm_subnet" "snet-finance" {
  provider = azurerm.mission-critical-staging 
  name                 = "snet-finance-${var.environment}-${var.region}"
  resource_group_name  = azurerm_resource_group.rg-finance.name
  virtual_network_name = azurerm_virtual_network.vnet-finance.name
  address_prefixes     = ["10.0.2.0/24"]
}



resource "azurerm_network_interface" "nic-finance-vm1" {
  provider = azurerm.mission-critical-staging 
  name                = "nic-finance-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-finance.location
  resource_group_name = azurerm_resource_group.rg-finance.name

  ip_configuration {
    name                          = "finance-ip"
    subnet_id                     = azurerm_subnet.snet-finance.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.pip-finance.id 
  }
}


resource "azurerm_network_security_group" "nsg-finance-vm1" {
  provider = azurerm.mission-critical-staging 
  name                = "nsg-finance-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-finance.location
  resource_group_name = azurerm_resource_group.rg-finance.name

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


resource "azurerm_network_interface_security_group_association" "nsg-association-finance-vm1" {
  provider = azurerm.mission-critical-staging 
  network_interface_id      = azurerm_network_interface.nic-finance-vm1.id
  network_security_group_id = azurerm_network_security_group.nsg-finance-vm1.id
}


resource "azurerm_linux_virtual_machine" "vm-finance-1" {
  provider = azurerm.mission-critical-staging 
  name                  = "vm-finance-${var.environment}-${var.region}-1"
  location              = azurerm_resource_group.rg-finance.location
  resource_group_name   = azurerm_resource_group.rg-finance.name
  network_interface_ids = [azurerm_network_interface.nic-finance-vm1.id]
  size               = "Standard_A1_v2"


source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  
  
  os_disk {
    name                 = "osdisk-finance"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }


  computer_name                   = "finance-vm"
  admin_username                  = "azureuser"
  disable_password_authentication = true

    admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.tls-finance.public_key_openssh
  }


}



resource "tls_private_key" "tls-finance" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_public_ip" "pip-finance" {
  provider = azurerm.mission-critical-staging 
  name                = "pip-finance-${var.environment}-${var.region}"
  resource_group_name = azurerm_resource_group.rg-finance.name
  location            = azurerm_resource_group.rg-finance.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "${var.environment}"
  }
}

resource "azurerm_kubernetes_cluster" "aks-finance" {
  provider = azurerm.mission-critical-staging 
  azure_policy_enabled = "true"
  name                = "aks-finance-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-finance.location
  resource_group_name = azurerm_resource_group.rg-finance.name
  dns_prefix          = "safemarch-aks-finance"


  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.finance-server-identity.id]
  }



  tags = {
    Environment = "${var.environment}"
  }
}


##### ecomm application resources:




resource "azurerm_container_registry" "cr-ecomm" {
  provider = azurerm.mission-critical-staging 
  name                = "crecomm${var.environment}${var.region}"
  resource_group_name = azurerm_resource_group.rg-ecomm.name
  location            = azurerm_resource_group.rg-ecomm.location
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





resource "azurerm_role_assignment" "roleassingment-ecomm" {
  provider = azurerm.mission-critical-staging 
  scope                = data.azurerm_subscription.mission-critical-staging.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.ecomm-server-identity.principal_id
}


resource "azurerm_user_assigned_identity" "ecomm-server-identity" {
  provider = azurerm.mission-critical-staging 
  resource_group_name   = azurerm_resource_group.rg-ecomm.name
  location = "${var.region}"
  name = "ecomm-server-identity"
}



resource "azurerm_resource_group" "rg-ecomm" {
  provider = azurerm.mission-critical-staging 
  name     = "rg-ecomm-${var.environment}"
  location = "${var.region}"
}



resource "azurerm_mysql_server" "mysql-ecomm" {
  provider = azurerm.mission-critical-staging 
  name                = "mysql-ecomm-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-ecomm.location
  resource_group_name = azurerm_resource_group.rg-ecomm.name

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


resource "azurerm_storage_account" "st-ecomm" {
  provider = azurerm.mission-critical-staging 
  name                     = "stecomm${var.environment}${var.region}"
  resource_group_name      = azurerm_resource_group.rg-ecomm.name
  location                 = azurerm_resource_group.rg-ecomm.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "plan-ecomm" {
  provider = azurerm.mission-critical-staging 
  name                = "plan-ecomm-${var.environment}-${var.region}"
  resource_group_name = azurerm_resource_group.rg-ecomm.name
  location            = azurerm_resource_group.rg-ecomm.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "func-ecomm" {
  provider = azurerm.mission-critical-staging 
  name                = "func-ecomm-${var.environment}-${var.region}"
  resource_group_name = azurerm_resource_group.rg-ecomm.name
  location            = azurerm_resource_group.rg-ecomm.location

  storage_account_name = azurerm_storage_account.st-ecomm.name
  service_plan_id      = azurerm_service_plan.plan-ecomm.id

  site_config {}
}


resource "azurerm_virtual_network" "vnet-ecomm" {
  provider = azurerm.mission-critical-staging 
  name                = "vnet-ecomm-${var.environment}-${var.region}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg-ecomm.location
  resource_group_name = azurerm_resource_group.rg-ecomm.name
}



resource "azurerm_subnet" "snet-ecomm" {
  provider = azurerm.mission-critical-staging 
  name                 = "snet-ecomm-${var.environment}-${var.region}"
  resource_group_name  = azurerm_resource_group.rg-ecomm.name
  virtual_network_name = azurerm_virtual_network.vnet-ecomm.name
  address_prefixes     = ["10.0.2.0/24"]
}



resource "azurerm_network_interface" "nic-ecomm-vm1" {
  provider = azurerm.mission-critical-staging 
  name                = "nic-ecomm-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-ecomm.location
  resource_group_name = azurerm_resource_group.rg-ecomm.name

  ip_configuration {
    name                          = "ecomm-ip"
    subnet_id                     = azurerm_subnet.snet-ecomm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.pip-ecomm.id 
  }
}


resource "azurerm_network_security_group" "nsg-ecomm-vm1" {
  provider = azurerm.mission-critical-staging 
  name                = "nsg-ecomm-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-ecomm.location
  resource_group_name = azurerm_resource_group.rg-ecomm.name

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


resource "azurerm_network_interface_security_group_association" "nsg-association-ecomm-vm1" {
  provider = azurerm.mission-critical-staging 
  network_interface_id      = azurerm_network_interface.nic-ecomm-vm1.id
  network_security_group_id = azurerm_network_security_group.nsg-ecomm-vm1.id
}


resource "azurerm_linux_virtual_machine" "vm-ecomm-1" {
  provider = azurerm.mission-critical-staging 
  name                  = "vm-ecomm-${var.environment}-${var.region}-1"
  location              = azurerm_resource_group.rg-ecomm.location
  resource_group_name   = azurerm_resource_group.rg-ecomm.name
  network_interface_ids = [azurerm_network_interface.nic-ecomm-vm1.id]
  size               = "Standard_A1_v2"


source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  
  
  os_disk {
    name                 = "osdisk-ecomm"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }


  computer_name                   = "ecomm-vm"
  admin_username                  = "azureuser"
  disable_password_authentication = true

    admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.tls-ecomm.public_key_openssh
  }


}



resource "tls_private_key" "tls-ecomm" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_public_ip" "pip-ecomm" {
  provider = azurerm.mission-critical-staging 
  name                = "pip-ecomm-${var.environment}-${var.region}"
  resource_group_name = azurerm_resource_group.rg-ecomm.name
  location            = azurerm_resource_group.rg-ecomm.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "${var.environment}"
  }
}

resource "azurerm_kubernetes_cluster" "aks-ecomm" {
  provider = azurerm.mission-critical-staging 
  azure_policy_enabled = "true"
  name                = "aks-ecomm-${var.environment}-${var.region}"
  location            = azurerm_resource_group.rg-ecomm.location
  resource_group_name = azurerm_resource_group.rg-ecomm.name
  dns_prefix          = "safemarch-aks-ecomm"


  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.ecomm-server-identity.id]
  }



  tags = {
    Environment = "${var.environment}"
  }
}






