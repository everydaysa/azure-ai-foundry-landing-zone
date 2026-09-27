variable "name_prefix" {
  description = "Prefix used to name the VNet links, e.g. \"aifz-dev\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-20 lowercase letters, digits or hyphens."
  }
}

variable "resource_group_name" {
  description = "Existing resource group that will own the zones."
  type        = string
}

variable "virtual_network_id" {
  description = "ID of the VNet whose workloads must resolve the private endpoints."
  type        = string

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+$", var.virtual_network_id))
    error_message = "virtual_network_id must be a full Azure VNet resource ID."
  }
}

variable "zones" {
  description = <<-EOT
    Private DNS zones to create, keyed by a short logical name that other
    modules use to look the zone up. Defaults cover every service in this
    landing zone. AI Foundry needs THREE zones because one account answers on
    three hostnames (Cognitive Services, OpenAI-compatible API, AI Services).
  EOT
  type        = map(string)
  default = {
    cognitiveservices = "privatelink.cognitiveservices.azure.com"
    openai            = "privatelink.openai.azure.com"
    aiservices        = "privatelink.services.ai.azure.com"
    keyvault          = "privatelink.vaultcore.azure.net"
    acr               = "privatelink.azurecr.io"
  }

  validation {
    condition     = alltrue([for z in values(var.zones) : startswith(z, "privatelink.")])
    error_message = "Every zone must be a privatelink.* zone - this module only serves Private Endpoints."
  }
}

variable "extra_zones" {
  description = "Additional privatelink zones merged into `zones`, e.g. { aks = \"privatelink.eastus2.azmk8s.io\" }."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for z in values(var.extra_zones) : startswith(z, "privatelink.")])
    error_message = "Every extra zone must be a privatelink.* zone."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
