output "zone_ids" {
  description = "Zone resource IDs keyed by logical name (cognitiveservices, openai, aiservices, keyvault, acr, ...). Private Endpoints reference these."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}

output "zone_names" {
  description = "Zone names keyed by logical name."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.name }
}

output "vnet_link_ids" {
  description = "VNet link IDs keyed by logical name. Private Endpoints should depend on these so DNS works the moment they exist."
  value       = { for k, l in azurerm_private_dns_zone_virtual_network_link.this : k => l.id }
}
