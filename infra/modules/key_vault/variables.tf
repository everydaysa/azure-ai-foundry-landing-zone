variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"aifz-dev\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-20 lowercase letters, digits or hyphens."
  }
}

variable "name_suffix" {
  description = "Short random suffix (from the stack) that makes the globally unique vault name, e.g. \"x7k2\"."
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

variable "tenant_id" {
  description = "Entra tenant that authenticates requests to the vault."
  type        = string
}

variable "sku_name" {
  description = "standard (software-protected keys) or premium (HSM-backed keys)."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be standard or premium."
  }
}

variable "soft_delete_retention_days" {
  description = "Days a deleted vault/secret is recoverable (7-90). Purge protection is always on, so this is also how long a torn-down vault's name stays reserved."
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Subnet where the vault's Private Endpoint is created (network module output)."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of the privatelink.vaultcore.azure.net zone (private_dns module output)."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Central workspace for audit logs and metrics (monitoring module output)."
  type        = string
}

variable "secrets_user_principal_ids" {
  description = <<-EOT
    Workload identities that may READ secrets (Key Vault Secrets User), keyed by
    a static name, e.g. { app = <principal id> }. Static keys keep for_each
    plannable even when the principal ID is only known after apply.
  EOT
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
