# ─── AI Foundry module ────────────────────────────────────────────────────
#
#   AKS pod ──(Entra token + "Cognitive Services OpenAI User")──443──┐
#                                                                    ▼
#            pe-ais-<prefix>-<suffix> (10.x.4.y) ──▶ ais-<prefix>-<suffix>  kind = AIServices
#   A records in 3 zones:                              ├─ local_auth_enabled = false   ← NO API keys
#     privatelink.cognitiveservices.azure.com          ├─ public network access OFF
#     privatelink.openai.azure.com                     ├─ outbound access restricted
#     privatelink.services.ai.azure.com                ├─ Foundry project
#                                                      └─ model deployment(s)
#                         allLogs + AllMetrics ─▶ central Log Analytics workspace

locals {
  account_name = "ais-${var.name_prefix}-${var.name_suffix}"
}

resource "azurerm_cognitive_account" "this" {
  #checkov:skip=CKV2_AZURE_22:Microsoft-managed keys (FIPS 140-2, AES-256) are used; customer-managed keys are the documented regulated-workload extension - see ADR-0005.

  name                = local.account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "AIServices"
  sku_name            = "S0"

  # A custom subdomain is REQUIRED for Entra ID token auth and Private Endpoints.
  custom_subdomain_name = local.account_name

  # THE headline control: key-based auth is switched off, so API keys cannot be
  # used even if someone lists them. Every call needs an Entra ID token.
  local_auth_enabled = false

  # No public endpoint - reachable only through the Private Endpoint below.
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "None"
  }

  # Data-exfiltration guard: the account itself may not call out to arbitrary
  # internet destinations (empty FQDN allow-list).
  outbound_network_access_restricted = true
  fqdns                              = []

  # Enables Foundry projects on this account.
  project_management_enabled = true

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ─── Foundry project ──────────────────────────────────────────────────────
resource "azurerm_cognitive_account_project" "this" {
  name                 = var.project_name
  cognitive_account_id = azurerm_cognitive_account.this.id
  location             = var.location
  display_name         = "${var.name_prefix} ${var.project_name}"
  description          = "Foundry project for the ${var.name_prefix} landing zone."

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ─── Model deployments ────────────────────────────────────────────────────
resource "azurerm_cognitive_deployment" "this" {
  for_each = var.model_deployments

  name                 = each.key
  cognitive_account_id = azurerm_cognitive_account.this.id

  model {
    format  = "OpenAI"
    name    = each.value.model_name
    version = each.value.model_version
  }

  sku {
    name     = each.value.sku_name
    capacity = each.value.capacity
  }

  # Pinned for reproducible behaviour; Azure moves it forward only when the
  # pinned version is retired, so the deployment never silently breaks.
  version_upgrade_option = "OnceCurrentVersionExpired"

  # Microsoft's default content filter (hate, sexual, violence, self-harm,
  # jailbreak / prompt-injection shields).
  rai_policy_name = "Microsoft.DefaultV2"
}

# ─── Private Endpoint (one PE, three DNS zones) ───────────────────────────
resource "azurerm_private_endpoint" "this" {
  name                          = "pe-${local.account_name}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${local.account_name}"

  private_service_connection {
    name                           = "psc-${local.account_name}"
    private_connection_resource_id = azurerm_cognitive_account.this.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  # One endpoint, three hostnames: Cognitive Services, OpenAI-compatible API,
  # and AI Services / Foundry. Each gets an A record in its own zone.
  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      var.private_dns_zone_ids["cognitiveservices"],
      var.private_dns_zone_ids["openai"],
      var.private_dns_zone_ids["aiservices"],
    ]
  }

  tags = var.tags
}

# ─── Telemetry → central workspace ────────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "diag-to-central-workspace"
  target_resource_id         = azurerm_cognitive_account.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # allLogs = Audit + RequestResponse (caller identity, deployment, status,
  # latency, 429 throttling, content-filter results) + Trace.
  enabled_log {
    category_group = "allLogs"
  }

  # Token usage, latency, throttling and availability metrics.
  enabled_metric {
    category = "AllMetrics"
  }
}

# ─── Who may call the models ──────────────────────────────────────────────
resource "azurerm_role_assignment" "openai_user" {
  for_each = var.openai_user_principal_ids

  scope                = azurerm_cognitive_account.this.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
  description          = "Inference-only access for workload '${each.key}' (Entra token via workload identity)."
}
