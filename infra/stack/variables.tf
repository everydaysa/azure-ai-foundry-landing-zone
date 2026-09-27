# ─── Identity of the environment ──────────────────────────────────────────
variable "project" {
  description = "Short project code - must match the bootstrap (it names rg-<project>-<environment>)."
  type        = string
  default     = "aifz"
}

variable "environment" {
  description = "Environment name: dev or prod."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "location" {
  description = "Azure region for every resource."
  type        = string
  default     = "eastus2"
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}

# ─── Network ──────────────────────────────────────────────────────────────
variable "address_space" {
  description = "VNet /16 for this environment (must not overlap other environments)."
  type        = string
}

# ─── Monitoring ───────────────────────────────────────────────────────────
variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
}

variable "log_daily_quota_gb" {
  description = "Daily ingestion cap in GB (-1 = unlimited)."
  type        = number
}

# ─── Key Vault ────────────────────────────────────────────────────────────
variable "key_vault_soft_delete_days" {
  description = "Key Vault soft-delete retention (7-90 days)."
  type        = number
}

# ─── AKS ──────────────────────────────────────────────────────────────────
variable "kubernetes_version" {
  description = "Kubernetes major.minor, or null for the AKS default."
  type        = string
  default     = null
}

variable "aks_sku_tier" {
  description = "Free (dev) or Standard (prod, API server SLA)."
  type        = string
}

variable "aks_node_vm_size" {
  description = "Node VM size."
  type        = string
  default     = "Standard_D2ds_v5"
}

variable "aks_availability_zones" {
  description = "Zones for the AKS node pool; [] for regional placement."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "aks_node_min_count" {
  description = "Autoscaler minimum nodes."
  type        = number
}

variable "aks_node_max_count" {
  description = "Autoscaler maximum nodes."
  type        = number
}

# ─── AI Foundry ───────────────────────────────────────────────────────────
variable "model_deployments" {
  description = "Model deployments (see the ai_foundry module). Check regional availability and quota first."
  type = map(object({
    model_name    = string
    model_version = string
    sku_name      = string
    capacity      = number
  }))
}
