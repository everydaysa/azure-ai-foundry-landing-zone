variable "name_prefix" {
  description = "Prefix for resource names, e.g. \"aifz-dev\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-20 lowercase letters, digits or hyphens."
  }
}

variable "name_suffix" {
  description = "Short random suffix (from the stack) that makes the globally unique account name and subdomain."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,6}$", var.name_suffix))
    error_message = "name_suffix must be 3-6 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region (must offer the chosen models and SKUs)."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to deploy into."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet where the Foundry Private Endpoint is created (network module output)."
  type        = string
}

variable "private_dns_zone_ids" {
  description = <<-EOT
    The three privatelink zones one AIServices account answers on, keyed exactly
    as the private_dns module outputs them: cognitiveservices, openai, aiservices.
  EOT
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["cognitiveservices", "openai", "aiservices"] : contains(keys(var.private_dns_zone_ids), k)])
    error_message = "private_dns_zone_ids must contain cognitiveservices, openai and aiservices - missing one breaks that API."
  }
}

variable "log_analytics_workspace_id" {
  description = "Central workspace for request/audit logs and metrics (monitoring module output)."
  type        = string
}

variable "project_name" {
  description = "Foundry project name (the workspace teams build in)."
  type        = string
  default     = "platform"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.project_name))
    error_message = "project_name must be 3-32 lowercase letters, digits or hyphens."
  }
}

variable "model_deployments" {
  description = <<-EOT
    Model deployments keyed by deployment name (the name the app calls).
      model_name     e.g. "gpt-4.1-mini"
      model_version  pinned version, e.g. "2025-04-14"
      sku_name       DataZoneStandard (US data zone) | GlobalStandard | Standard
      capacity       thousands of tokens per minute (TPM) - must fit your quota
  EOT
  type = map(object({
    model_name    = string
    model_version = string
    sku_name      = string
    capacity      = number
  }))

  validation {
    condition     = alltrue([for d in values(var.model_deployments) : contains(["DataZoneStandard", "GlobalStandard", "Standard"], d.sku_name)])
    error_message = "sku_name must be DataZoneStandard, GlobalStandard or Standard (pay-as-you-go SKUs only)."
  }

  validation {
    condition     = alltrue([for d in values(var.model_deployments) : d.capacity >= 1 && d.capacity <= 1000])
    error_message = "capacity must be between 1 and 1000 (thousand TPM)."
  }
}

variable "openai_user_principal_ids" {
  description = <<-EOT
    Workload identities allowed to CALL the models (Cognitive Services OpenAI
    User), keyed by a static name, e.g. { app = <principal id> }. This role can
    run inference but cannot read keys, change deployments or manage the account.
  EOT
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
