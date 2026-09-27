variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"aifz-dev\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-20 lowercase letters, digits or hyphens."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to deploy into."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant used for cluster authentication."
  type        = string
}

variable "vnet_id" {
  description = "VNet ID - the cluster identity gets Network Contributor here to join the node subnet."
  type        = string
}

variable "aks_nodes_subnet_id" {
  description = "Subnet for the node pool (network module output; already associated with the NAT Gateway)."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Central workspace for Container Insights and control-plane logs."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes major.minor (e.g. \"1.33\"). null = AKS default; patch versions are applied automatically."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "Free (dev, no SLA) or Standard (99.95% API server SLA - use in prod)."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard"], var.sku_tier)
    error_message = "sku_tier must be Free or Standard."
  }
}

variable "node_vm_size" {
  description = "VM size for the node pool. D*ds_v5 sizes have a local temp disk, enabling ephemeral OS disks."
  type        = string
  default     = "Standard_D2ds_v5"
}

variable "node_min_count" {
  description = "Autoscaler minimum node count."
  type        = number
  default     = 2

  validation {
    condition     = var.node_min_count >= 1 && var.node_min_count <= var.node_max_count
    error_message = "node_min_count must be at least 1 and not greater than node_max_count."
  }
}

variable "node_max_count" {
  description = "Autoscaler maximum node count."
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_count >= 1 && var.node_max_count <= 20
    error_message = "node_max_count must be between 1 and 20."
  }
}

variable "node_os_disk_size_gb" {
  description = "Ephemeral OS disk size - must fit in the VM's temp disk (75 GiB on D2ds_v5)."
  type        = number
  default     = 64
}

variable "availability_zones" {
  description = "Zones to spread nodes across."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "app_namespace" {
  description = "Kubernetes namespace of the application workload."
  type        = string
  default     = "ai-app"
}

variable "app_service_account" {
  description = "Kubernetes ServiceAccount the application runs as (bound to the app's managed identity)."
  type        = string
  default     = "foundry-app"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
