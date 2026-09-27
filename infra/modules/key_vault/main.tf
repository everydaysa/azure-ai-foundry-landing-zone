# ─── Key Vault module ─────────────────────────────────────────────────────
#
#   AKS pod (workload identity, Key Vault Secrets User)
#     └─ tcp/443 ─▶ pe-kv-<prefix> (10.x.4.y) ─▶ kv-<prefix>-<suffix>
#                         ▲                        public access: DISABLED
#   privatelink.vaultcore.azure.net  (A record written by the DNS zone group)
#                                     AuditEvent + metrics ─▶ central workspace
#
# Separation of duties: the pipeline that deploys this vault has only
# control-plane rights (Contributor). It holds no data-plane role, so it can
# create the vault but can never read the secrets inside it.

# Deliberately NO `prevent_destroy` here (unlike the Terraform state account):
#  - Azure itself guarantees recoverability: purge protection + soft delete keep
#    a destroyed vault and every secret restorable for the retention period, and
#    nobody (not even an Owner) can purge them early. That is a stronger,
#    platform-enforced guarantee than a Terraform-only lifecycle flag.
#  - prevent_destroy must be a literal (it cannot vary per environment), so it
#    would also block the intended `make destroy ENV=dev` teardown.
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_key_vault" "this" {
  name                = "kv-${var.name_prefix}-${var.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = var.sku_name

  # Azure RBAC for data-plane access; no legacy access policies.
  rbac_authorization_enabled = true

  # Recoverability: deleted vaults/secrets can be restored, and nobody - not
  # even an Owner - can purge them before the retention period ends.
  purge_protection_enabled   = true
  soft_delete_retention_days = var.soft_delete_retention_days

  # Private Endpoint only.
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "None"
  }

  # No VM / ARM-template / disk-encryption side doors.
  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = false

  tags = var.tags
}

resource "azurerm_private_endpoint" "this" {
  name                          = "pe-${azurerm_key_vault.this.name}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${azurerm_key_vault.this.name}"

  private_service_connection {
    name                           = "psc-${azurerm_key_vault.this.name}"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  # Writes the A record into privatelink.vaultcore.azure.net automatically.
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "diag-to-central-workspace"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # allLogs = AuditEvent (every get/set/delete, with the caller's identity)
  # + AzurePolicyEvaluationDetails.
  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_role_assignment" "secrets_user" {
  for_each = var.secrets_user_principal_ids

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
  description          = "Read-only secret access for workload '${each.key}' (via workload identity)."
}
