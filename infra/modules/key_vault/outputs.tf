output "id" {
  description = "Key Vault resource ID."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "Data-plane URI (resolves to the Private Endpoint inside the VNet)."
  value       = azurerm_key_vault.this.vault_uri
}

output "private_endpoint_ip" {
  description = "Private IP of the vault's endpoint in the PE subnet."
  value       = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
}
