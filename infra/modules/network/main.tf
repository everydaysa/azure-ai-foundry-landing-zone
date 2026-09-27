# ─── Network module ───────────────────────────────────────────────────────
#
#  vnet-<prefix>  (/16)
#  ├── snet-aks-nodes          /22  ── NSG: no inbound from Internet
#  │        │                         NAT Gateway ──▶ one static egress IP
#  └── snet-private-endpoints  /24  ── NSG: ONLY tcp/443 from AKS nodes; no outbound
#
#  default_outbound_access_enabled = false on every subnet: nothing reaches the
#  internet unless we give it an explicit, known path (the NAT Gateway).

locals {
  aks_nodes_prefix         = cidrsubnet(var.address_space, 6, 0) # x.x.0.0/22
  private_endpoints_prefix = cidrsubnet(var.address_space, 8, 4) # x.x.4.0/24

  private_endpoint_sources = distinct(concat([local.aks_nodes_prefix], var.private_endpoint_allowed_sources))
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  tags                = var.tags
}

# ─── Subnets ──────────────────────────────────────────────────────────────
resource "azurerm_subnet" "aks_nodes" {
  name                            = "snet-aks-nodes"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [local.aks_nodes_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "private_endpoints" {
  name                            = "snet-private-endpoints"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [local.private_endpoints_prefix]
  default_outbound_access_enabled = false

  # Without this, NSGs are silently IGNORED for Private Endpoints.
  private_endpoint_network_policies = "Enabled"
}

# ─── NSG: AKS nodes ───────────────────────────────────────────────────────
# Azure's default rules already allow VNet + Azure Load Balancer traffic and
# deny everything else inbound. The explicit rule documents intent: this
# platform exposes nothing to the internet (access is via kubectl port-forward
# or an internal ingress).
resource "azurerm_network_security_group" "aks_nodes" {
  name                = "nsg-${var.name_prefix}-aks-nodes"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "deny-internet-inbound"
    description                = "No inbound traffic from the internet to cluster nodes."
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

# ─── NSG: Private Endpoints (micro-segmentation) ──────────────────────────
resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-${var.name_prefix}-private-endpoints"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                         = "allow-https-from-workloads"
    description                  = "Only AKS nodes (and approved sources) may call Foundry, Key Vault and ACR."
    priority                     = 100
    direction                    = "Inbound"
    access                       = "Allow"
    protocol                     = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "443"
    source_address_prefixes      = local.private_endpoint_sources
    destination_address_prefixes = [local.private_endpoints_prefix]
  }

  security_rule {
    name                       = "deny-all-other-inbound"
    description                = "Everything else inside the VNet is denied (overrides the default AllowVnetInBound)."
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-outbound"
    description                = "Private Endpoints only answer requests; they never initiate connections."
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "aks_nodes" {
  subnet_id                 = azurerm_subnet.aks_nodes.id
  network_security_group_id = azurerm_network_security_group.aks_nodes.id
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

# ─── Egress: NAT Gateway with one static public IP ────────────────────────
resource "azurerm_public_ip" "nat" {
  name                = "pip-${var.name_prefix}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "ng-${var.name_prefix}"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.nat_idle_timeout_minutes
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Only the AKS node subnet gets egress. Private Endpoints never need it.
resource "azurerm_subnet_nat_gateway_association" "aks_nodes" {
  subnet_id      = azurerm_subnet.aks_nodes.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}
