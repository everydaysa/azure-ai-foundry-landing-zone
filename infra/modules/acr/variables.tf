variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"aifz-dev\" (hyphens are stripped for the registry name)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-20 lowercase letters, digits or hyphens."
  }
}

variable "name_suffix" {
  description = "Short random suffix (from the stack) that makes the globally unique registry name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,6}$", var.name_suffix))
    error_message = "name_suffix must be 3-6 lowercase letters or digits."
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

variable "private_endpoint_subnet_id" {
  description = "Subnet where the registry's Private Endpoint is created (network module output)."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of the privatelink.azurecr.io zone (private_dns module output)."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Central workspace for login/repository events and metrics (monitoring module output)."
  type        = string
}

variable "zone_redundancy_enabled" {
  description = "Spread the registry across availability zones. No extra cost on Premium in zone-enabled regions (e.g. eastus2). Forces replacement if changed."
  type        = bool
  default     = true
}

variable "untagged_retention_days" {
  description = "Days before untagged manifests are purged (keeps the registry clean; 0 disables)."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_retention_days >= 0 && var.untagged_retention_days <= 365
    error_message = "untagged_retention_days must be between 0 and 365."
  }
}

variable "acr_pull_principal_ids" {
  description = <<-EOT
    Identities allowed to PULL images (AcrPull), keyed by a static name, e.g.
    { aks_kubelet = <principal id> }. Pushing is granted separately to the CI
    deploy identity by the bootstrap (AcrPush at resource-group scope).
  EOT
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
