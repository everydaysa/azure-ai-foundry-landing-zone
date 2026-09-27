# ─── Monitoring module: ONE control room for every signal ─────────────────
#
#   AI Foundry · AKS · Key Vault · ACR · NSGs ──(diagnostic settings)──┐
#                                                                      ▼
#                                            log-<prefix>  Log Analytics workspace
#                                                                      ▲
#   FastAPI app ──(OpenTelemetry, Entra auth)──▶ appi-<prefix> ────────┘
#                                               (workspace-based App Insights)
#
# Local (key-based) auth is DISABLED on both resources: the connection string
# only says WHERE to send telemetry. Sending requires an Entra token plus the
# "Monitoring Metrics Publisher" role, so a leaked connection string can
# neither inject nor spoof data.

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku               = "PerGB2018"
  retention_in_days = var.retention_in_days
  daily_quota_gb    = var.daily_quota_gb

  # Entra ID only: no shared workspace keys for ingestion or query.
  local_authentication_enabled = false

  # Resource-context RBAC: a team with access to a resource can read that
  # resource's logs without being granted the whole workspace.
  allow_resource_only_permissions = true

  tags = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"

  # Workspace-based: App Insights data is stored IN the workspace above, so
  # app traces and platform logs can be joined in one KQL query.
  workspace_id = azurerm_log_analytics_workspace.this.id

  # Entra-only ingestion (see header comment).
  local_authentication_enabled = false

  # Keep App Insights' own cap aligned with the workspace cap.
  daily_data_cap_in_gb = var.daily_quota_gb == -1 ? 100 : var.daily_quota_gb

  tags = var.tags
}
