terraform {
  required_version = ">= 1.0.0"
}

provider "azurerm" {
  features {}
}

data "azurerm_subscription" "current" {}

/*
	Create network resource group
*/
resource "azurerm_resource_group" "network_rg" {
  name     = "${var.prefix}-${var.environment}-network-rg"
  location = var.location
}

/*
	Create log resource group
*/
resource "azurerm_resource_group" "log_rg" {
  name     = "${var.prefix}-${var.environment}-log-rg"
  location = var.location
}

/*
	Create jump box resource group
*/
resource "azurerm_resource_group" "jb_rg" {
  name     = "${var.prefix}-${var.environment}-jb-rg"
  location = var.location
}

/*
	Create log analytics workspace
*/
resource "azurerm_log_analytics_workspace" "log_ws" {
  name                = "${var.prefix}-${var.environment}-log"
  resource_group_name = azurerm_resource_group.log_rg.name
  location            = azurerm_resource_group.log_rg.location

  sku               = "PerGB2018"
  retention_in_days = 30
}

/*
	Create storage account to store log data
*/
resource "azurerm_storage_account" "log_sa" {
  name                = "${var.prefix}${var.environment}logsa"
  resource_group_name = azurerm_resource_group.log_rg.name
  location            = azurerm_resource_group.log_rg.location

  account_tier              = "Standard"
  account_kind              = "StorageV2"
  account_replication_type  = "LRS"
  allow_blob_public_access  = false
  enable_https_traffic_only = true
  min_tls_version           = "TLS1_2"
}

/*
	Create event hub namespace
*/
resource "azurerm_eventhub_namespace" "log_ehns" {
  name                = "${var.prefix}-${var.environment}-ns"
  resource_group_name = azurerm_resource_group.log_rg.name
  location            = azurerm_resource_group.log_rg.location

  sku      = "Standard"
  capacity = 1
}

/*
	Create event hub namespace authorization rule
*/
resource "azurerm_eventhub_namespace_authorization_rule" "log_ehns_authrule" {
  name                = "send-logs"
  resource_group_name = azurerm_resource_group.log_rg.name
  namespace_name      = azurerm_eventhub_namespace.log_ehns.name

  listen = false
  send   = true
  manage = false
}

/*
	Create event hub
*/
resource "azurerm_eventhub" "log_eh" {
  name                = "${var.prefix}-${var.environment}-eh"
  resource_group_name = azurerm_resource_group.log_rg.name
  namespace_name      = azurerm_eventhub_namespace.log_ehns.name

  partition_count   = 2
  message_retention = 1
}

/*
	Create Azure AD diagnostic settings
*/
resource "azurerm_monitor_aad_diagnostic_setting" "example" {
  name = "stream-to-la-sa-eh"

  log_analytics_workspace_id     = azurerm_log_analytics_workspace.log_ws.id
  storage_account_id             = azurerm_storage_account.log_sa.id
  eventhub_name                  = azurerm_eventhub.log_eh.name
  eventhub_authorization_rule_id = azurerm_eventhub_namespace_authorization_rule.log_ehns_authrule.id

  log {
    category = "AuditLogs"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 1
    }
  }

  log {
    category = "SignInLogs"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 1
    }
  }

  log {
    category = "NonInteractiveUserSignInLogs"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 1
    }
  }

  log {
    category = "ServicePrincipalSignInLogs"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 1
    }
  }

  log {
    category = "ManagedIdentitySignInLogs"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 1
    }
  }

  log {
    category = "ProvisioningLogs"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 1
    }
  }

  log {
    category = "ADFSSignInLogs"
    enabled  = true

    retention_policy {}
  }

  log {
    category = "RiskyUsers"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 1
    }
  }

  log {
    category = "UserRiskEvents"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 1
    }
  }
}

/*
	Create activity log diagnostic settings
*/
resource "azurerm_monitor_diagnostic_setting" "activity_log_diagnostics" {
  name               = "stream-to-la-sa-eh"
  target_resource_id = data.azurerm_subscription.current.id

  log_analytics_workspace_id     = azurerm_log_analytics_workspace.log_ws.id
  storage_account_id             = azurerm_storage_account.log_sa.id
  eventhub_name                  = azurerm_eventhub.log_eh.name
  eventhub_authorization_rule_id = azurerm_eventhub_namespace_authorization_rule.log_ehns_authrule.id

  log {
    category = "Administrative"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "Security"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "ServiceHealth"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "Alert"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "Recommendation"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "Policy"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "Autoscale"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "ResourceHealth"

    retention_policy {
      enabled = false
    }
  }
}

/*  
	Create Network Watcher
	Please note only one instance of Network Watcher can be created per region. Per default a
	Network Watcher instance is created automatically when a virtual network is created. This can be disabled as 
	documented under https://docs.microsoft.com/en-us/azure/network-watcher/network-watcher-create#opt-out-of-network-watcher-automatic-enablement 
*/
resource "azurerm_network_watcher" "nw" {
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = azurerm_resource_group.network_rg.name
  location            = azurerm_resource_group.network_rg.location
}

/*
	Create virtual network
*/
module "hub_vnet" {
  source              = "./modules/virtual_network"
  name                = "${var.prefix}-${var.environment}-hub-vnet"
  resource_group_name = azurerm_resource_group.network_rg.name
  location            = azurerm_resource_group.network_rg.location

  address_space = ["10.0.0.0/16"]
  subnets = [
    {
      name : "DefaultSubnet"
      address_prefixes : ["10.0.0.0/24"]
    }
  ]
}

/*
	Create basic network security group
*/
resource "azurerm_network_security_group" "hub_nsg" {
  name                = "${var.prefix}-${var.environment}-hub-vnet-nsg"
  resource_group_name = azurerm_resource_group.network_rg.name
  location            = azurerm_resource_group.network_rg.location
}

/*
	Import possible Log and Metric categories for a given resource. This could be useful to iterate
	over log and metric categories, as they are different for each resource.
*/
data "azurerm_monitor_diagnostic_categories" "hub_nsg_diag_categories" {
  resource_id = azurerm_network_security_group.hub_nsg.id
}

/*
	Create diagnostic settings for a network security group.
	For this sample the enabled log categories will be send to a log analytics workspace,
	a storage account and an eventhub. Please note that only one of them is required to send logs and metrics.
*/
resource "azurerm_monitor_diagnostic_setting" "hub_nsg_diag" {
  name               = "stream-to-la-sa-eh"
  target_resource_id = azurerm_network_security_group.hub_nsg.id

  log_analytics_workspace_id     = azurerm_log_analytics_workspace.log_ws.id
  storage_account_id             = azurerm_storage_account.log_sa.id
  eventhub_name                  = azurerm_eventhub.log_eh.name
  eventhub_authorization_rule_id = azurerm_eventhub_namespace_authorization_rule.log_ehns_authrule.id

  /*
  log {
	category = "NetworkSecurityGroupEvent"
	enabled  = true
  }

  log {
	category = "NetworkSecurityGroupRuleCounter"
	enabled  = true
  }
  */

  // sample to iterate over the different log categories and metrics (if available)
  dynamic "log" {
    for_each = data.azurerm_monitor_diagnostic_categories.hub_nsg_diag_categories.logs
    content {
      category = log.value
      enabled  = true
      retention_policy {
        enabled = true
        days    = 7
      }
    }
  }

  dynamic "metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.hub_nsg_diag_categories.metrics
    content {
      category = metric.value
      enabled  = true
      retention_policy {
        enabled = true
        days    = 7
      }
    }
  }
}

/*
	Create network flow log configuration and store flow logs in a given storage account.
	Traffic analytics is optional and can be disabled.
*/
resource "azurerm_network_watcher_flow_log" "hub_flow_log" {
  network_watcher_name = azurerm_network_watcher.nw.name
  resource_group_name  = azurerm_resource_group.network_rg.name

  network_security_group_id = azurerm_network_security_group.hub_nsg.id
  storage_account_id        = azurerm_storage_account.log_sa.id
  enabled                   = true

  retention_policy {
    enabled = true
    days    = 7
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.log_ws.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.log_ws.location
    workspace_resource_id = azurerm_log_analytics_workspace.log_ws.id
    interval_in_minutes   = 10
  }
}

/*
	Create NIC for VM
*/
resource "azurerm_network_interface" "vm_nic" {
  name                = "vm-nic"
  resource_group_name = azurerm_resource_group.jb_rg.name
  location            = azurerm_resource_group.jb_rg.location


  ip_configuration {
    name                          = "ipconfig0"
    subnet_id                     = module.hub_vnet.subnet_ids["DefaultSubnet"]
    private_ip_address_allocation = "Dynamic"
  }
}

/*
	Create Jump Box VM (Ubuntu 18.04 LTS)
*/
resource "azurerm_linux_virtual_machine" "jb_vm" {
  name                = "${var.prefix}-${var.environment}-jb-vm"
  resource_group_name = azurerm_resource_group.jb_rg.name
  location            = azurerm_resource_group.jb_rg.location

  size           = "Standard_D2s_v3"
  admin_username = "azureadmin"

  network_interface_ids = [
    azurerm_network_interface.vm_nic.id
  ]

  admin_ssh_key {
    username   = "azureadmin"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  identity {
	type = "SystemAssigned"
  }
}

/*
	Import possible Log and Metric categories for a given resource.
*/
data "azurerm_monitor_diagnostic_categories" "jb_vm_diag_categories" {
  resource_id = azurerm_linux_virtual_machine.jb_vm.id
}

/*
	Create VM diagnostic settings - platform metrics only
*/
resource "azurerm_monitor_diagnostic_setting" "jb_vm_diag" {
  name               = "stream-to-la-sa-eh"
  target_resource_id = azurerm_linux_virtual_machine.jb_vm.id

  log_analytics_workspace_id     = azurerm_log_analytics_workspace.log_ws.id
  storage_account_id             = azurerm_storage_account.log_sa.id
  eventhub_name                  = azurerm_eventhub.log_eh.name
  eventhub_authorization_rule_id = azurerm_eventhub_namespace_authorization_rule.log_ehns_authrule.id

  dynamic "metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.jb_vm_diag_categories.metrics
    content {
      category = metric.value
      enabled  = true
      retention_policy {
        enabled = true
        days    = 7
      }
    }
  }
}

/*
	Create SAS for LAD
*/
data "azurerm_storage_account_sas" "lad_diag_sas" {
  connection_string = azurerm_storage_account.log_sa.primary_blob_connection_string
  https_only        = true

  resource_types {
    service   = false
    container = true
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = true
    file  = false
  }

  start  = "2021-11-01T00:00:00Z"
  expiry = "2021-11-30T00:00:00Z"

  permissions {
    read    = false
    write   = true
    delete  = false
    list    = true
    add     = true
    create  = true
    update  = true
    process = false
  }
}

resource "azurerm_virtual_machine_extension" "jb_vm_diag" {
  name                       = "DiagExtension"
  virtual_machine_id         = azurerm_linux_virtual_machine.jb_vm.id
  publisher                  = "Microsoft.Azure.Diagnostics"
  type                       = "LinuxDiagnostic"
  type_handler_version       = "4.0"
  auto_upgrade_minor_version = true

  settings = templatefile("lad_config.json", { vm_id = azurerm_linux_virtual_machine.jb_vm.id, lad_storage_account = azurerm_storage_account.log_sa.name })

  protected_settings = <<PROTECTED_SETTINGS
	{
		"storageAccountName": "${azurerm_storage_account.log_sa.name}",
		"storageAccountSasToken": "${data.azurerm_storage_account_sas.lad_diag_sas.sas}",
		"sinksConfig": {
			"sink": [
				{
					"name": "EventHubSink",
					"type": "EventHub",
					"sasURL": "###ENTER EVENTHUB SAS TOKEN HERE###"
				},
				{
					"name": "JsonSink",
					"type": "JsonBlob"
				}
			]
		}
	}
PROTECTED_SETTINGS
}

/*

*/
resource "azurerm_virtual_machine_extension" "jb_vm_mma" {
  name                       = "MMAExtension"
  virtual_machine_id         = azurerm_linux_virtual_machine.jb_vm.id
  publisher                  = "Microsoft.EnterpriseCloud.Monitoring"
  type                       = "OmsAgentForLinux"
  type_handler_version       = "1.13"
  auto_upgrade_minor_version = "true"

  settings = <<SETTINGS
	{
	  "workspaceId": "${azurerm_log_analytics_workspace.log_ws.workspace_id}"
	}
	SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
	{
	  "workspaceKey": "${azurerm_log_analytics_workspace.log_ws.primary_shared_key}"
	}
	PROTECTED_SETTINGS
}
