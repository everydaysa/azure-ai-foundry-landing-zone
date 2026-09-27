# ─── Container Registry module ────────────────────────────────────────────
#
#  GitHub Actions ──(JIT: add own IP → push with Entra token → remove IP)──┐
#                                                                          ▼
#                        acr<prefix><suffix>  Premium, firewall default DENY, 0 IP rules at rest
#  AKS kubelet ──AcrPull──▶ pe-acr… (10.x.4.y) ─┘  admin user OFF, anonymous pull OFF
#     privatelink.azurecr.io: login server + dedicated data endpoint records
#                        login + repository events ─▶ central Log Analytics workspace
#
# "Just-in-time" access: at rest the public endpoint is reachable by NOBODY
# (default_action = Deny, no IP rules). The CD workflow adds its runner's IP,
# pushes, and removes it in an always() step. Terraform also defines "no IP
# rules" as the desired state, so any rule left behind is removed on the next
# apply - the design self-heals.

locals {
  registry_name = "acr${replace(var.name_prefix, "-", "")}${var.name_suffix}"
}

resource "azurerm_container_registry" "this" {
  #checkov:skip=CKV_AZURE_139:Public endpoint is deny-by-default with zero IP rules at rest; CI opens it just-in-time for its own IP only. See ADR-0006.
  #checkov:skip=CKV_AZURE_166:Quarantine needs a scanner to release images; images are scanned (Trivy) in CI before push and Defender for Containers scans at rest. See ADR-0006.
  #checkov:skip=CKV_AZURE_165:Geo-replication is unnecessary for a single-region landing zone; enable per region when expanding.
  #checkov:skip=CKV_AZURE_164:Docker Content Trust is retired by Azure; supply-chain integrity comes from digest pinning + SBOM (Step 14).

  name                = local.registry_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Premium" # required for Private Endpoints, retention and data endpoints

  # Identity-only access: no shared admin password, no anonymous pulls.
  admin_enabled          = false
  anonymous_pull_enabled = false

  # Deny-by-default firewall; no IP rules at rest (see header).
  public_network_access_enabled = true
  network_rule_bypass_option    = "None"

  network_rule_set {
    default_action = "Deny"
  }

  # Dedicated per-region data endpoints (<name>.<region>.data.azurecr.io):
  # image layers are served from a hostname the firewall and PE can scope.
  data_endpoint_enabled = true

  retention_policy_in_days = var.untagged_retention_days
  zone_redundancy_enabled  = var.zone_redundancy_enabled

  tags = var.tags
}

resource "azurerm_private_endpoint" "this" {
  name                          = "pe-${local.registry_name}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${local.registry_name}"

  private_service_connection {
    name                           = "psc-${local.registry_name}"
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  # Registers BOTH the login server and the regional data endpoint in
  # privatelink.azurecr.io, so image pulls from AKS never leave the VNet.
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "diag-to-central-workspace"
  target_resource_id         = azurerm_container_registry.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # allLogs = ContainerRegistryLoginEvents (who authenticated, from where)
  #         + ContainerRegistryRepositoryEvents (push / pull / delete).
  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  for_each = var.acr_pull_principal_ids

  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
  description          = "Pull-only access for '${each.key}'."
}
