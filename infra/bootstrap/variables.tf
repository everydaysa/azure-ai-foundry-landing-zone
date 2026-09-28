variable "location" {
  description = "Azure region for the bootstrap resources and the landing-zone resource groups."
  type        = string
  default     = "eastus2"
}

variable "project" {
  description = "Short project code used in every resource name."
  type        = string
  default     = "aifz"

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.project))
    error_message = "project must be 2-6 lowercase letters/digits (it is embedded in storage account names)."
  }
}

variable "environments" {
  description = "Environments that get their own resource group and deploy identity."
  type        = set(string)
  default     = ["dev", "prod"]
}

variable "github_owner" {
  description = "GitHub organisation or user that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the owner)."
  type        = string
}

variable "github_owner_id" {
  description = <<-EOT
    Numeric ID of the GitHub owner (gh api repos/<owner>/<repo> --jq .owner.id).
    Newer repositories put immutable IDs in the OIDC subject
    ("repo:<owner>@<owner_id>/<repo>@<repo_id>:..."), so a deleted-and-recreated
    repo with the same name can't inherit the Azure trust. null = classic
    name-only subject.
  EOT
  type        = number
  default     = null
}

variable "github_repo_id" {
  description = "Numeric ID of the GitHub repository (gh api repos/<owner>/<repo> --jq .id). See github_owner_id."
  type        = number
  default     = null

  validation {
    condition     = (var.github_repo_id == null) == (var.github_owner_id == null)
    error_message = "Set both github_owner_id and github_repo_id, or neither."
  }
}

variable "operator_object_ids" {
  description = <<-EOT
    Extra Entra object IDs (humans or groups) who operate the platform. They get
    state-blob access and AKS cluster-admin on the environment resource groups.
    The identity running the bootstrap is always included automatically.
  EOT
  type        = set(string)
  default     = []
}

variable "pipeline_assignable_roles" {
  description = <<-EOT
    Allow-list of built-in roles the deploy identities may assign (ABAC-constrained
    RBAC Administrator). Anything not listed - notably Owner, User Access
    Administrator and RBAC Administrator itself - can never be granted by CI.
  EOT
  type        = set(string)
  default = [
    "AcrPull",
    "Cognitive Services OpenAI User",
    "Cognitive Services User",
    "Key Vault Secrets User",
    "Monitoring Metrics Publisher",
    "Network Contributor",
    "Private DNS Zone Contributor",
  ]
}

variable "enable_state_delete_lock" {
  description = "Put a CanNotDelete lock on the state storage account."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}
