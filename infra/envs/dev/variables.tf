# Types only - the VALUES for this environment are in terraform.tfvars.
# Descriptions and validation live in the stack and modules.

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "address_space" {
  description = "VNet /16."
  type        = string
}

variable "log_retention_days" {
  description = "Log Analytics retention (days)."
  type        = number
}

variable "log_daily_quota_gb" {
  description = "Daily ingestion cap in GB (-1 = unlimited)."
  type        = number
}

variable "key_vault_soft_delete_days" {
  description = "Key Vault soft-delete retention (days)."
  type        = number
}

variable "kubernetes_version" {
  description = "Kubernetes major.minor or null."
  type        = string
  default     = null
}

variable "aks_sku_tier" {
  description = "AKS tier: Free or Standard."
  type        = string
}

variable "aks_node_vm_size" {
  description = "AKS node VM size."
  type        = string
}

variable "aks_availability_zones" {
  description = "AKS node pool zones ([] = regional)."
  type        = list(string)
}

variable "aks_node_min_count" {
  description = "AKS autoscaler minimum."
  type        = number
}

variable "aks_node_max_count" {
  description = "AKS autoscaler maximum."
  type        = number
}

variable "model_deployments" {
  description = "AI Foundry model deployments."
  type = map(object({
    model_name    = string
    model_version = string
    sku_name      = string
    capacity      = number
  }))
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
