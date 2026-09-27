data "azurerm_client_config" "current" {}

locals {
  repo_full_name = "${var.github_owner}/${var.github_repo}"

  tags = merge({
    project    = var.project
    managed_by = "terraform"
    layer      = "bootstrap"
    repository = local.repo_full_name
  }, var.tags)
}

# Storage account names are globally unique, so add a short random suffix.
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# ─── Bootstrap resource group: state + CI identities ──────────────────────
resource "azurerm_resource_group" "bootstrap" {
  name     = "rg-${var.project}-bootstrap"
  location = var.location
  tags     = local.tags
}

# ─── Environment resource groups ──────────────────────────────────────────
# Created HERE (by the Owner) rather than by the stack so each environment's
# deploy identity can be scoped to exactly one resource group. The dev
# pipeline therefore has no permissions at all on prod.
resource "azurerm_resource_group" "env" {
  for_each = var.environments

  name     = "rg-${var.project}-${each.key}"
  location = var.location
  tags     = merge(local.tags, { environment = each.key, layer = "landing-zone" })
}

# ─── Terraform remote state ───────────────────────────────────────────────
resource "azurerm_storage_account" "tfstate" {
  #checkov:skip=CKV_AZURE_33:Queue service is not used by this account.
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed keys + infrastructure encryption are sufficient for state; CMK is a documented enterprise extension (ADR-0002).
  #checkov:skip=CKV_AZURE_59:Public endpoint kept (Entra-only, no shared keys) so GitHub-hosted runners can reach state; see ADR-0002.
  #checkov:skip=CKV_AZURE_35:Same as CKV_AZURE_59 - network default action Allow is required for GitHub-hosted runners; see ADR-0002.
  #checkov:skip=CKV2_AZURE_33:Private endpoint for state is the documented self-hosted-runner extension; see ADR-0002.
  #checkov:skip=CKV_AZURE_206:ZRS gives zone redundancy for state; geo-replication is unnecessary for a rebuildable demo platform.

  name                = "st${var.project}tfstate${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = azurerm_resource_group.bootstrap.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "ZRS"

  # Identity-only access: no account keys, no SAS tokens, no local users.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false
  sftp_enabled                    = false

  # Transport + data protection.
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  infrastructure_encryption_enabled = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false

  # See ADR-0002: reachable from GitHub-hosted runners, but only with an Entra token.
  public_network_access = "Enabled"

  blob_properties {
    versioning_enabled  = true # every state write is recoverable
    change_feed_enabled = true # audit trail of blob changes

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags
}

# Created through the ARM control plane (storage_account_id), so it works
# even though shared-key access is disabled.
resource "azurerm_storage_container" "tfstate" {
  #checkov:skip=CKV2_AZURE_21:Blob change feed + versioning provide the state audit trail; routing blob diagnostic logs to the central workspace is listed in ADR-0002.

  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

resource "azurerm_management_lock" "tfstate" {
  count = var.enable_state_delete_lock ? 1 : 0

  name       = "lock-tfstate-cannot-delete"
  scope      = azurerm_storage_account.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Protects Terraform state for every environment. Remove deliberately before teardown."
}
