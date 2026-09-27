output "vnet_id" {
  description = "Virtual network ID (used for Private DNS zone links)."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Virtual network name."
  value       = azurerm_virtual_network.this.name
}

output "aks_nodes_subnet_id" {
  description = "Subnet ID for the AKS node pools."
  value       = azurerm_subnet.aks_nodes.id
}

output "private_endpoints_subnet_id" {
  description = "Subnet ID where every Private Endpoint is placed."
  value       = azurerm_subnet.private_endpoints.id
}

output "subnet_prefixes" {
  description = "CIDR of each subnet, for documentation and NSG reasoning."
  value = {
    aks_nodes         = local.aks_nodes_prefix
    private_endpoints = local.private_endpoints_prefix
  }
}

output "nat_gateway_id" {
  description = "NAT Gateway ID (AKS uses outbound_type = userAssignedNATGateway)."
  value       = azurerm_nat_gateway.this.id
}

output "egress_public_ip" {
  description = "The single static IP all cluster egress leaves from - give this to any partner that needs to allow-list you."
  value       = azurerm_public_ip.nat.ip_address
}
