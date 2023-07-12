terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}
provider "azurerm" {
  features {}
}


resource "azurerm_resource_group" "rg" {
  name     = "cool-wordpress-rg"
  location = "eastus"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "wordpress-vnet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["192.168.0.0/16"]
}

resource "azurerm_subnet" "gateway" {
  name                 = "gateway-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.168.0.0/24"]
  service_endpoints    = ["Microsoft.Web"]
}

resource "azurerm_subnet" "mysql" {
  name                 = "mysql-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.168.3.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet" "app" {
  name                 = "app-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.168.2.0/24"]

  delegation {
    name = "cool-app-delegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}


resource "azurerm_public_ip" "pip" {
  name                = "gateway-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}


resource "azurerm_application_gateway" "appgw" {
  name                = "cool-appgateway"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gateway-ip-configuration"
    subnet_id = azurerm_subnet.gateway.id
  }

  frontend_port {
    name = "cool-fe-port-name"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "cool-fe-ip-config-name"
    public_ip_address_id = azurerm_public_ip.pip.id
  }

  backend_address_pool {
    name  = "cool-be-address-pool"
    fqdns = [azurerm_linux_web_app.webapp.default_hostname]
  }

  backend_http_settings {
    name                                = "cool-http-setting"
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    probe_name                          = "cool-app-probe"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true
  }

  http_listener {
    name                           = "cool-listener"
    frontend_ip_configuration_name = "cool-fe-ip-config-name"
    frontend_port_name             = "cool-fe-port-name"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "cool-request-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "cool-listener"
    backend_address_pool_name  = "cool-be-address-pool"
    backend_http_settings_name = "cool-http-setting"
    priority                   = 1
  }

  probe {
    host                                      = azurerm_linux_web_app.webapp.default_hostname
    interval                                  = 60
    minimum_servers                           = 0
    name                                      = "cool-app-probe"
    path                                      = "/"
    pick_host_name_from_backend_http_settings = false
    port                                      = 80
    protocol                                  = "Http"
    timeout                                   = 60
    unhealthy_threshold                       = 3

    match {
      status_code = []
    }
  }
}


resource "azurerm_service_plan" "asp" {
  name                = "cool-wordpress-asp"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "webapp" {
  name                      = "cool-wordpress-app"
  location                  = azurerm_resource_group.rg.location
  resource_group_name       = azurerm_resource_group.rg.name
  service_plan_id           = azurerm_service_plan.asp.id
  virtual_network_subnet_id = azurerm_subnet.app.id
  https_only                = false


  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "WORDPRESS_DB_HOST"                   = azurerm_mysql_flexible_server.mysql_server.fqdn
    "WORDPRESS_DB_NAME"                   = azurerm_mysql_flexible_database.mysql_db.name
    "WORDPRESS_DB_USER"                   = "CoolAdminUser"
    "WORDPRESS_DB_PASSWORD"               = random_password.mysql.result
  }

  site_config {
    minimum_tls_version = "1.2"

    application_stack {
      docker_image_name   = "wordpress:latest"
      docker_registry_url = "https://index.docker.io"
    }
    ip_restriction {
      action                    = "Allow"
      headers                   = []
      name                      = "GW"
      priority                  = 100
      virtual_network_subnet_id = azurerm_subnet.gateway.id
    }
  }
}

resource "random_password" "mysql" {
  length  = 64
  special = false
}


resource "azurerm_mysql_flexible_server" "mysql_server" {
  name                   = "cool-mysqlserver"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  administrator_login    = "CoolAdminUser"
  administrator_password = random_password.mysql.result
  backup_retention_days  = 7
  delegated_subnet_id    = azurerm_subnet.mysql.id
  private_dns_zone_id    = azurerm_private_dns_zone.pvt_dns_zone.id
  sku_name               = "GP_Standard_D2ds_v4"

  depends_on = [azurerm_private_dns_zone_virtual_network_link.vnet_link]
}

resource "azurerm_private_dns_zone" "pvt_dns_zone" {
  name                = "cool.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link" {
  name                  = "cool-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.pvt_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  resource_group_name   = azurerm_resource_group.rg.name
}


resource "azurerm_mysql_flexible_database" "mysql_db" {
  name                = "cool-wordpress-db"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql_server.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}