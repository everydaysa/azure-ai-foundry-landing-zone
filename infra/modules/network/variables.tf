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

variable "address_space" {
  description = <<-EOT
    The VNet address space. Must be a /16. Subnets are carved from it
    deterministically so every environment has an identical layout:
      .0.0/22  AKS nodes          (1,019 usable IPs; pods use CNI Overlay)
      .4.0/24  Private Endpoints  (251 usable IPs)
      .5.0+    reserved for growth (API-server subnet, self-hosted runners, ...)
  EOT
  type        = string

  validation {
    condition     = can(cidrhost(var.address_space, 0)) && endswith(var.address_space, "/16")
    error_message = "address_space must be a valid IPv4 /16, e.g. \"10.10.0.0/16\"."
  }
}

variable "private_endpoint_allowed_sources" {
  description = <<-EOT
    Extra CIDRs allowed to reach Private Endpoints on 443 (for example a
    self-hosted runner subnet). The AKS node subnet is always allowed.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.private_endpoint_allowed_sources : can(cidrhost(c, 0))])
    error_message = "Every entry must be a valid CIDR."
  }
}

variable "nat_idle_timeout_minutes" {
  description = "NAT Gateway TCP idle timeout (4-120 minutes)."
  type        = number
  default     = 10

  validation {
    condition     = var.nat_idle_timeout_minutes >= 4 && var.nat_idle_timeout_minutes <= 120
    error_message = "nat_idle_timeout_minutes must be between 4 and 120."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
