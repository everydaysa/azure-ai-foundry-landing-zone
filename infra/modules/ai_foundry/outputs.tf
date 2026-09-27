output "id" {
  description = "AI Foundry (AIServices) account resource ID."
  value       = azurerm_cognitive_account.this.id
}

output "name" {
  description = "Account name (also its custom subdomain)."
  value       = azurerm_cognitive_account.this.name
}

output "endpoint" {
  description = "Account endpoint. Inside the VNet it resolves to the Private Endpoint IP."
  value       = azurerm_cognitive_account.this.endpoint
}

output "openai_endpoint" {
  description = "OpenAI-compatible endpoint the app calls with an Entra token."
  value       = "https://${azurerm_cognitive_account.this.custom_subdomain_name}.openai.azure.com/"
}

output "project_id" {
  description = "Foundry project resource ID."
  value       = azurerm_cognitive_account_project.this.id
}

output "deployment_names" {
  description = "Model deployment names the app can call."
  value       = keys(azurerm_cognitive_deployment.this)
}

output "account_principal_id" {
  description = "The account's own managed identity (for future connections, e.g. AI Search)."
  value       = azurerm_cognitive_account.this.identity[0].principal_id
}
