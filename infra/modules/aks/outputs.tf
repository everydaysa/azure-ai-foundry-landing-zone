output "id" {
  description = "AKS cluster resource ID."
  value       = azurerm_kubernetes_cluster.this.id
}

output "name" {
  description = "Cluster name (used by `az aks command invoke`)."
  value       = azurerm_kubernetes_cluster.this.name
}

output "oidc_issuer_url" {
  description = "The cluster's OIDC issuer - the 'note-printer' Entra ID trusts for workload identity."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubelet_object_id" {
  description = "Kubelet identity object ID - the stack grants it AcrPull on the registry."
  # kubelet_identity is filled in by Azure when the cluster is created. Until
  # then (e.g. a plan against a mocked provider) the list can be empty, so
  # fall back to null instead of failing on [0]. In a real plan the value is
  # simply "known after apply".
  value = try(azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id, null)
}

output "app_identity_client_id" {
  description = "Client ID the app's ServiceAccount is annotated with (azure.workload.identity/client-id)."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "app_identity_principal_id" {
  description = "Principal ID of the app identity - the stack grants it Foundry, Key Vault and App Insights roles."
  value       = azurerm_user_assigned_identity.app.principal_id
}

output "app_namespace" {
  description = "Namespace the workload identity is bound to."
  value       = var.app_namespace
}

output "app_service_account" {
  description = "ServiceAccount the workload identity is bound to."
  value       = var.app_service_account
}

output "node_resource_group" {
  description = "Auto-generated resource group holding node VMs, load balancer and the private DNS zone."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}
