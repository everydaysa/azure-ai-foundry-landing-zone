# Pass-through of the stack outputs, so `terraform output` in this folder
# gives CI and operators everything they need to deploy the app.

output "resource_group_name" {
  description = "Environment resource group."
  value       = module.stack.resource_group_name
}

output "aks_name" {
  description = "AKS cluster name."
  value       = module.stack.aks_name
}

output "app_namespace" {
  description = "App namespace."
  value       = module.stack.app_namespace
}

output "app_service_account" {
  description = "App ServiceAccount."
  value       = module.stack.app_service_account
}

output "app_identity_client_id" {
  description = "Workload identity client ID for the ServiceAccount annotation."
  value       = module.stack.app_identity_client_id
}

output "acr_name" {
  description = "Registry name."
  value       = module.stack.acr_name
}

output "acr_login_server" {
  description = "Registry hostname."
  value       = module.stack.acr_login_server
}

output "foundry_openai_endpoint" {
  description = "OpenAI-compatible endpoint."
  value       = module.stack.foundry_openai_endpoint
}

output "foundry_deployment_names" {
  description = "Model deployment names."
  value       = module.stack.foundry_deployment_names
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = module.stack.key_vault_uri
}

output "log_analytics_workspace_id" {
  description = "Central workspace ID."
  value       = module.stack.log_analytics_workspace_id
}

output "application_insights_connection_string" {
  description = "App Insights connection string (not a credential; Entra auth required)."
  value       = module.stack.application_insights_connection_string
  sensitive   = true
}

output "egress_public_ip" {
  description = "Cluster egress IP."
  value       = module.stack.egress_public_ip
}
