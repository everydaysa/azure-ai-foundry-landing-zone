output "id" {
  description = "Container registry resource ID."
  value       = azurerm_container_registry.this.id
}

output "name" {
  description = "Registry name (used by `az acr` commands in CI)."
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "Registry hostname for image references, e.g. <name>.azurecr.io/app@sha256:..."
  value       = azurerm_container_registry.this.login_server
}
