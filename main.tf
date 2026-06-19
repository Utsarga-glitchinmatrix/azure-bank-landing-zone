terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.32.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "d8e55574-5bf1-4400-91e5-1cf773bd9d84"
}

############################################################
# RESOURCE GROUPS
############################################################
resource "azurerm_resource_group" "Bank_Hub" {
  location = var.location
  name     = "Bank-Hub-RG"
}

resource "azurerm_resource_group" "Bank_Spoke" {
  location = var.location
  name     = "Bank-Spoke-RG"
}

############################################################
# HUB VNET
############################################################
module "hub_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.19.0"

  name          = "Hub-VNet"
  parent_id     = azurerm_resource_group.Bank_Hub.id
  location      = var.location
  address_space = ["192.168.0.0/16"]

  subnets = {
    AzureFirewallSubnet = {
      name             = "AzureFirewallSubnet"
      address_prefixes = ["192.168.1.0/26"]
    }
    AzureFirewallManagementSubnet = {
      name             = "AzureFirewallManagementSubnet"
      address_prefixes = ["192.168.3.0/26"]
    }
    AzureBastionSubnet = {
      name             = "AzureBastionSubnet"
      address_prefixes = ["192.168.2.0/26"]
    }
  }

  peerings = {
    for spoke_key, _cfg in var.spokes : spoke_key => {
      name                                  = "hub-to-${spoke_key}"
      remote_virtual_network_resource_id    = module.spoke_vnet[spoke_key].resource_id
      allow_forwarded_traffic               = true
      allow_gateway_transit                 = false
      allow_virtual_network_access          = true
      do_not_verify_remote_gateways         = false
      enable_only_ipv6_peering              = false
      use_remote_gateways                   = false
      create_reverse_peering                = true
      reverse_name                          = "${spoke_key}-to-hub"
      reverse_allow_forwarded_traffic       = false
      reverse_allow_gateway_transit         = false
      reverse_allow_virtual_network_access  = true
      reverse_do_not_verify_remote_gateways = false
      reverse_enable_only_ipv6_peering      = false
      reverse_use_remote_gateways           = false
    }
  }
}

############################################################
# SPOKE VNETs
############################################################
module "spoke_vnet" {
  source   = "Azure/avm-res-network-virtualnetwork/azurerm"
  version  = "0.19.0"
  for_each = var.spokes

  name          = "SPOKE-VNET-${each.key}"
  parent_id     = azurerm_resource_group.Bank_Spoke.id
  location      = var.location
  address_space = each.value.address_space

  subnets = {
    for i, a in each.value.subnet_names : a => {
      name             = a
      address_prefixes = [each.value.subnet_prefixes[i]]
    }
  }
}

############################################################
# FIREWALL PUBLIC IPs
############################################################
resource "azurerm_public_ip" "firewall_hub_ip" {
  name                = "Hub-Firewall-IP"
  location            = azurerm_resource_group.Bank_Hub.location
  resource_group_name = azurerm_resource_group.Bank_Hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "firewall_mgmt_ip" {
  name                = "Hub-Firewall-Mgmt-IP"
  location            = azurerm_resource_group.Bank_Hub.location
  resource_group_name = azurerm_resource_group.Bank_Hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

############################################################
# FIREWALL POLICY
############################################################
resource "azurerm_firewall_policy" "hub_fw_policy" {
  name                = "bank-fw-policy"
  resource_group_name = azurerm_resource_group.Bank_Hub.name
  location            = azurerm_resource_group.Bank_Hub.location
  sku                 = "Basic"
}

resource "azurerm_firewall_policy_rule_collection_group" "spoke_spoke_comm" {
  name               = "spoke-to-spoke-rcg"
  firewall_policy_id = azurerm_firewall_policy.hub_fw_policy.id
  priority           = 500

  network_rule_collection {
    name     = "spoke-to-spoke-rules"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "spoke1-to-spoke2"
      protocols             = ["Any"]
      source_addresses      = ["10.0.0.0/16"]
      destination_addresses = ["10.1.0.0/16"]
      destination_ports     = ["*"]
    }

    rule {
      name                  = "spoke2-to-spoke1"
      protocols             = ["Any"]
      source_addresses      = ["10.1.0.0/16"]
      destination_addresses = ["10.0.0.0/16"]
      destination_ports     = ["*"]
    }
  }
}

############################################################
# FIREWALL
############################################################
resource "azurerm_firewall" "firewall_hub" {
  name                = "hub-firewall"
  location            = azurerm_resource_group.Bank_Hub.location
  resource_group_name = azurerm_resource_group.Bank_Hub.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"
  firewall_policy_id  = azurerm_firewall_policy.hub_fw_policy.id

  ip_configuration {
    name                 = "configuration"
    subnet_id            = module.hub_vnet.subnets["AzureFirewallSubnet"].resource_id
    public_ip_address_id = azurerm_public_ip.firewall_hub_ip.id
  }

  management_ip_configuration {
    name                 = "management"
    subnet_id            = module.hub_vnet.subnets["AzureFirewallManagementSubnet"].resource_id
    public_ip_address_id = azurerm_public_ip.firewall_mgmt_ip.id
  }
}

############################################################
# BASTION PUBLIC IP
############################################################
resource "azurerm_public_ip" "Bastion_Public_Ip" {
  name                = "Public-Ip-Bastion"
  location            = azurerm_resource_group.Bank_Hub.location
  resource_group_name = azurerm_resource_group.Bank_Hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

############################################################
# BASTION
############################################################
resource "azurerm_bastion_host" "Bastion_Hub" {
  name                = "Bastion-hub"
  location            = azurerm_resource_group.Bank_Hub.location
  resource_group_name = azurerm_resource_group.Bank_Hub.name
  sku                 = "Basic"

  ip_configuration {
    name                 = "configuration"
    subnet_id            = module.hub_vnet.subnets["AzureBastionSubnet"].resource_id
    public_ip_address_id = azurerm_public_ip.Bastion_Public_Ip.id
  }
}

############################################################
# LOG ANALYTICS WORKSPACE
############################################################
resource "azurerm_log_analytics_workspace" "hub_law" {
  name                = "hub-law"
  location            = azurerm_resource_group.Bank_Hub.location
  resource_group_name = azurerm_resource_group.Bank_Hub.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

############################################################
# DIAGNOSTIC SETTINGS — FIREWALL
############################################################
resource "azurerm_monitor_diagnostic_setting" "firewall_diag" {
  name                       = "firewall-diag"
  target_resource_id         = azurerm_firewall.firewall_hub.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hub_law.id

  enabled_log {
    category = "AzureFirewallApplicationRule"
  }
  enabled_log {
    category = "AzureFirewallNetworkRule"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

############################################################
# ACTION GROUP
############################################################
resource "azurerm_monitor_action_group" "security_team" {
  name                = "security-team-ag"
  resource_group_name = azurerm_resource_group.Bank_Hub.name
  short_name          = "secteam"

  email_receiver {
    name          = "security-email"
    email_address = "security@bank.com.au"
  }
}

############################################################
# ALERT RULE
############################################################
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "firewall_deny_alert" {
  name                 = "firewall-deny-alert"
  location             = azurerm_resource_group.Bank_Hub.location
  resource_group_name  = azurerm_resource_group.Bank_Hub.name
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [azurerm_log_analytics_workspace.hub_law.id]
  severity             = 2

  criteria {
    query = <<-QUERY
      AzureDiagnostics
      | where Category == "AzureFirewallNetworkRule"
      | where OperationName == "AzureFirewallNetworkRuleLog"
      | summarize count() by bin(TimeGenerated, 5m)
      | where count_ > 10
    QUERY
    time_aggregation_method = "Count"
    threshold               = 10
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.security_team.id]
  }
}

############################################################
# STORAGE ACCOUNT — SPOKE1
############################################################
resource "azurerm_storage_account" "Spoke_1_StorageAccount" {
  name                     = "stblobspoke1"
  resource_group_name      = azurerm_resource_group.Bank_Spoke.name
  location                 = azurerm_resource_group.Bank_Spoke.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "spoke1_container" {
  name                  = "content"
  storage_account_id    = azurerm_storage_account.Spoke_1_StorageAccount.id
  container_access_type = "private"
}

############################################################
# ROUTE TABLE
############################################################
resource "azurerm_route_table" "spoke_rt" {
  name                = "spoke-routetable"
  location            = azurerm_resource_group.Bank_Spoke.location
  resource_group_name = azurerm_resource_group.Bank_Spoke.name

  route {
    name                   = "to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.firewall_hub.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "subnet_0" {
  for_each = var.spokes

  subnet_id      = module.spoke_vnet[each.key].subnets[each.value.subnet_names[0]].resource_id
  route_table_id = azurerm_route_table.spoke_rt.id
}

resource "azurerm_subnet_route_table_association" "subnet_1" {
  subnet_id      = module.spoke_vnet["spoke1"].subnets[var.spokes["spoke1"].subnet_names[1]].resource_id
  route_table_id = azurerm_route_table.spoke_rt.id
}

############################################################
# NSGs
############################################################
resource "azurerm_network_security_group" "spoke1_nsg" {
  name                = "spoke1-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.Bank_Spoke.name

  security_rule {
    name                       = "allow-bastion-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "192.168.2.0/26"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "22"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_network_security_group" "spoke2_nsg" {
  name                = "spoke2-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.Bank_Spoke.name

  security_rule {
    name                       = "allow-bastion-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "192.168.2.0/26"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "22"
  }

  security_rule {
    name                       = "allow-lb-inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "80"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "spoke1_nsg_assoc" {
  subnet_id                 = module.spoke_vnet["spoke1"].subnets[var.spokes["spoke1"].subnet_names[0]].resource_id
  network_security_group_id = azurerm_network_security_group.spoke1_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "spoke2_nsg_assoc" {
  subnet_id                 = module.spoke_vnet["spoke2"].subnets[var.spokes["spoke2"].subnet_names[0]].resource_id
  network_security_group_id = azurerm_network_security_group.spoke2_nsg.id
}

############################################################
# NETWORK WATCHER
############################################################
resource "azurerm_network_watcher" "hub_nw" {
  name                = "NetworkWatcher_australiaeast"
  resource_group_name = "NetworkWatcherRG"
  location            = var.location
}

############################################################
# STORAGE ACCOUNT — FLOW LOGS
############################################################
resource "azurerm_storage_account" "flow_logs_sa" {
  name                     = "bankflowlogssa"
  resource_group_name      = azurerm_resource_group.Bank_Hub.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

############################################################
# VNET FLOW LOGS
############################################################
resource "azurerm_network_watcher_flow_log" "spoke1_flowlog" {
  name                 = "spoke1-vnet-flowlog"
  network_watcher_name = azurerm_network_watcher.hub_nw.name
  resource_group_name  = azurerm_network_watcher.hub_nw.resource_group_name
  target_resource_id   = module.spoke_vnet["spoke1"].resource_id
  storage_account_id   = azurerm_storage_account.flow_logs_sa.id
  enabled              = true
  version              = 2

  retention_policy {
    enabled = true
    days    = 7
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.hub_law.workspace_id
    workspace_region      = var.location
    workspace_resource_id = azurerm_log_analytics_workspace.hub_law.id
    interval_in_minutes   = 10
  }
}

resource "azurerm_network_watcher_flow_log" "spoke2_flowlog" {
  name                 = "spoke2-vnet-flowlog"
  network_watcher_name = azurerm_network_watcher.hub_nw.name
  resource_group_name  = azurerm_network_watcher.hub_nw.resource_group_name
  target_resource_id   = module.spoke_vnet["spoke2"].resource_id
  storage_account_id   = azurerm_storage_account.flow_logs_sa.id
  enabled              = true
  version              = 2

  retention_policy {
    enabled = true
    days    = 7
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.hub_law.workspace_id
    workspace_region      = var.location
    workspace_resource_id = azurerm_log_analytics_workspace.hub_law.id
    interval_in_minutes   = 10
  }
}

############################################################
# INTERNAL LOAD BALANCER — SPOKE2
############################################################
resource "azurerm_lb" "spoke2_ilb" {
  name                = "spoke2-internal-lb"
  location            = azurerm_resource_group.Bank_Spoke.location
  resource_group_name = azurerm_resource_group.Bank_Spoke.name
  sku                 = "Basic"

  frontend_ip_configuration {
    name                          = "spoke2-frontend"
    subnet_id                     = module.spoke_vnet["spoke2"].subnets["workload-subnet"].resource_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_backend_address_pool" "spoke2_backend" {
  name            = "spoke2-backend-pool"
  loadbalancer_id = azurerm_lb.spoke2_ilb.id
}

resource "azurerm_lb_probe" "spoke2_probe" {
  name                = "spoke2-health-probe"
  loadbalancer_id     = azurerm_lb.spoke2_ilb.id
  protocol            = "Tcp"
  port                = 80
  interval_in_seconds = 15
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "spoke2_rule" {
  name                           = "spoke2-lb-rule"
  loadbalancer_id                = azurerm_lb.spoke2_ilb.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "spoke2-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.spoke2_backend.id]
  probe_id                       = azurerm_lb_probe.spoke2_probe.id
}

############################################################
# VMSS — SPOKE2
############################################################
resource "azurerm_linux_virtual_machine_scale_set" "spoke2_vmss" {
  name                            = "spoke2-vmss"
  location                        = azurerm_resource_group.Bank_Spoke.location
  resource_group_name             = azurerm_resource_group.Bank_Spoke.name
  sku                             = "Standard_B2pls_v2"
  instances                       = 2
  admin_username                  = "adminuser"
  admin_password                  = "BankHub@123456!"
  disable_password_authentication = false

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-arm64"
    version   = "latest"
  }

  network_interface {
    name    = "spoke2-vmss-nic"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = module.spoke_vnet["spoke2"].subnets["workload-subnet"].resource_id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.spoke2_backend.id]
    }
  }
}

############################################################
# AUTOSCALE — SPOKE2 VMSS
############################################################
resource "azurerm_monitor_autoscale_setting" "spoke2_autoscale" {
  name                = "spoke2-autoscale"
  resource_group_name = azurerm_resource_group.Bank_Spoke.name
  location            = azurerm_resource_group.Bank_Spoke.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.spoke2_vmss.id

  profile {
    name = "default"

    capacity {
      default = 2
      minimum = 2
      maximum = 5
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.spoke2_vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 80
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.spoke2_vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 20
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}

############################################################
# VM — SPOKE1
############################################################
resource "azurerm_network_interface" "spoke1_vm_nic" {
  name                = "spoke1-vm-nic"
  location            = azurerm_resource_group.Bank_Spoke.location
  resource_group_name = azurerm_resource_group.Bank_Spoke.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.spoke_vnet["spoke1"].subnets["identity-subnet"].resource_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "spoke1_vm" {
  name                            = "spoke1-vm"
  location                        = azurerm_resource_group.Bank_Spoke.location
  resource_group_name             = azurerm_resource_group.Bank_Spoke.name
  size                            = "Standard_B2pls_v2"
  admin_username                  = "adminuser"
  admin_password                  = "BankHub@123456!"
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.spoke1_vm_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-arm64"
    version   = "latest"
  }
}