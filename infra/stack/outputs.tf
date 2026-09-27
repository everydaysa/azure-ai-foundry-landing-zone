# Everything the application deployment (Steps 11-12) and CI/CD (Step 14)
# need, in one place. None of these values is a secret: identities, endpoints
# and names only. The App Insights connection string is marked sensitive by the
# provider, but with local auth disabled it is not a credential.

output "resource_group_name" {
  description = "Environment resource group."
  value       = data.azurerm_resource_group.this.name
}

output "name_suffix" {
  description = "Random suffix shared by the globally unique resource names."
  value       = random_string.suffix.result
}

# ─── Kubernetes ───────────────────────────────────────────────────────────
output "aks_name" {
  description = "AKS cluster name (for `az aks command invoke`)."
  value       = module.aks.name
}

output "app_namespace" {
  description = "Namespace the app runs in."
  value       = module.aks.app_namespace
}

output "app_service_account" {
  description = "ServiceAccount bound to the app's workload identity."
  value       = module.aks.app_service_account
}

output "app_identity_client_id" {
  description = "Annotate the ServiceAccount with this (azure.workload.identity/client-id)."
  value       = module.aks.app_identity_client_id
}

# ─── Registry ─────────────────────────────────────────────────────────────
output "acr_name" {
  description = "Registry name (for `az acr` commands)."
  value       = module.acr.name
}

output "acr_login_server" {
  description = "Registry hostname for image references."
  value       = module.acr.login_server
}

# ─── AI Foundry ───────────────────────────────────────────────────────────
output "foundry_openai_endpoint" {
  description = "OpenAI-compatible endpoint the app calls (resolves privately inside the VNet)."
  value       = module.ai_foundry.openai_endpoint
}

output "foundry_deployment_names" {
  description = "Model deployment names the app can call."
  value       = module.ai_foundry.deployment_names
}

# ─── Key Vault & telemetry ────────────────────────────────────────────────
output "key_vault_uri" {
  description = "Key Vault data-plane URI."
  value       = module.key_vault.vault_uri
}

output "log_analytics_workspace_id" {
  description = "Central workspace resource ID."
  value       = module.monitoring.log_analytics_workspace_id
}

output "application_insights_connection_string" {
  description = "Where the app sends OpenTelemetry data (Entra auth still required)."
  value       = module.monitoring.application_insights_connection_string
  sensitive   = true
}

output "private_endpoints_cidr" {
  description = "Private Endpoint subnet - the app's NetworkPolicy allows 443 only to this range inside the VNet."
  value       = module.network.subnet_prefixes.private_endpoints
}

output "egress_public_ip" {
  description = "The single static IP all cluster egress leaves from."
  value       = module.network.egress_public_ip
}
