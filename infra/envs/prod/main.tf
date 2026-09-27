# prod environment - identical composition to every other environment
# (../../stack); only the values in terraform.tfvars differ.

module "stack" {
  source = "../../stack"

  environment                = var.environment
  location                   = var.location
  address_space              = var.address_space
  log_retention_days         = var.log_retention_days
  log_daily_quota_gb         = var.log_daily_quota_gb
  key_vault_soft_delete_days = var.key_vault_soft_delete_days
  kubernetes_version         = var.kubernetes_version
  aks_sku_tier               = var.aks_sku_tier
  aks_node_vm_size           = var.aks_node_vm_size
  aks_availability_zones     = var.aks_availability_zones
  aks_node_min_count         = var.aks_node_min_count
  aks_node_max_count         = var.aks_node_max_count
  model_deployments          = var.model_deployments
  tags                       = var.tags
}
