variable "name_prefix" {
  description = "Prefix for every resource name, e.g. \"aifz-dev\"."
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
  description = "Existing resource group to deploy into (created by the bootstrap)."
  type        = string
}

variable "retention_in_days" {
  description = "How long logs are kept in the workspace (30-730). dev: 30, prod: 90."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 30 and 730."
  }
}

variable "daily_quota_gb" {
  description = <<-EOT
    Daily ingestion cap in GB. -1 means unlimited. Use a cap in dev so a noisy
    bug cannot run up the bill; never cap prod (you must not drop security logs).
  EOT
  type        = number
  default     = -1

  validation {
    condition     = var.daily_quota_gb == -1 || var.daily_quota_gb >= 0.023
    error_message = "daily_quota_gb must be -1 (unlimited) or at least 0.023."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
