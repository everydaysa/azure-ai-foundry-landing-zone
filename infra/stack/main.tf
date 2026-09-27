# ─── The landing-zone stack ───────────────────────────────────────────────
#
# One composition, reused by every environment (envs/dev, envs/prod). It snaps
# the seven modules together and draws the permission lines between them.
#
#   network ─┬──────────────▶ private_dns ─┬─▶ key_vault
#            │                             ├─▶ ai_foundry
#   monitoring ─(workspace)─▶ everything   └─▶ acr
#            └──────────────────────────────▶ aks ─▶ app identity, kubelet identity
#
#   Permission lines (all principal_type = ServicePrincipal, so the bootstrap's
#   ABAC-constrained RBAC Administrator role permits CI to create them):
#     app identity  ─ Cognitive Services OpenAI User ─▶ AI Foundry
#     app identity  ─ Key Vault Secrets User         ─▶ Key Vault
#     app identity  ─ Monitoring Metrics Publisher   ─▶ App Insights
#     kubelet       ─ AcrPull                        ─▶ Container Registry
#     AKS cp        ─ Network Contributor            ─▶ VNet (inside the aks module)

data "azurerm_client_config" "current" {}

# Fails fast at plan time if the bootstrap has not created this environment's
# resource group (the deploy identity is scoped to exactly this group).
data "azurerm_resource_group" "this" {
  name = "rg-${var.project}-${var.environment}"
}

# ONE random suffix per environment, shared by every globally unique name
# (Key Vault, AI Foundry, ACR). Stored in state, so it never changes on re-plan.
resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = merge({
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
    layer       = "landing-zone"
  }, var.tags)

  common = {
    location            = var.location
    resource_group_name = data.azurerm_resource_group.this.name
    tags                = local.tags
  }
}

# ─── 1. Network ───────────────────────────────────────────────────────────
module "network" {
  source = "../modules/network"

  name_prefix         = local.name_prefix
  location            = local.common.location
  resource_group_name = local.common.resource_group_name
  address_space       = var.address_space
  tags                = local.common.tags
}

# ─── 2. Monitoring (the single control room) ──────────────────────────────
module "monitoring" {
  source = "../modules/monitoring"

  name_prefix         = local.name_prefix
  location            = local.common.location
  resource_group_name = local.common.resource_group_name
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.common.tags
}

# ─── 3. Private DNS (the internal phone book) ─────────────────────────────
module "private_dns" {
  source = "../modules/private_dns"

  name_prefix         = local.name_prefix
  resource_group_name = local.common.resource_group_name
  virtual_network_id  = module.network.vnet_id
  tags                = local.common.tags
}

# ─── 4. AKS (creates the app's workload identity) ─────────────────────────
module "aks" {
  source = "../modules/aks"

  name_prefix                = local.name_prefix
  location                   = local.common.location
  resource_group_name        = local.common.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  vnet_id                    = module.network.vnet_id
  aks_nodes_subnet_id        = module.network.aks_nodes_subnet_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  kubernetes_version         = var.kubernetes_version
  sku_tier                   = var.aks_sku_tier
  node_vm_size               = var.aks_node_vm_size
  availability_zones         = var.aks_availability_zones
  node_min_count             = var.aks_node_min_count
  node_max_count             = var.aks_node_max_count
  tags                       = local.common.tags

  # The NAT Gateway must be attached to the node subnet BEFORE the cluster is
  # created (outbound_type = userAssignedNATGateway checks for it).
  depends_on = [module.network]
}

# ─── 5. Key Vault ─────────────────────────────────────────────────────────
module "key_vault" {
  source = "../modules/key_vault"

  name_prefix                = local.name_prefix
  name_suffix                = random_string.suffix.result
  location                   = local.common.location
  resource_group_name        = local.common.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days = var.key_vault_soft_delete_days
  private_endpoint_subnet_id = module.network.private_endpoints_subnet_id
  private_dns_zone_id        = module.private_dns.zone_ids["keyvault"]
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  secrets_user_principal_ids = { app = module.aks.app_identity_principal_id }
  tags                       = local.common.tags
}

# ─── 6. AI Foundry ────────────────────────────────────────────────────────
module "ai_foundry" {
  source = "../modules/ai_foundry"

  name_prefix                = local.name_prefix
  name_suffix                = random_string.suffix.result
  location                   = local.common.location
  resource_group_name        = local.common.resource_group_name
  private_endpoint_subnet_id = module.network.private_endpoints_subnet_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  model_deployments          = var.model_deployments
  openai_user_principal_ids  = { app = module.aks.app_identity_principal_id }
  tags                       = local.common.tags

  private_dns_zone_ids = {
    cognitiveservices = module.private_dns.zone_ids["cognitiveservices"]
    openai            = module.private_dns.zone_ids["openai"]
    aiservices        = module.private_dns.zone_ids["aiservices"]
  }
}

# ─── 7. Container Registry ────────────────────────────────────────────────
module "acr" {
  source = "../modules/acr"

  name_prefix                = local.name_prefix
  name_suffix                = random_string.suffix.result
  location                   = local.common.location
  resource_group_name        = local.common.resource_group_name
  private_endpoint_subnet_id = module.network.private_endpoints_subnet_id
  private_dns_zone_id        = module.private_dns.zone_ids["acr"]
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  acr_pull_principal_ids     = { aks_kubelet = module.aks.kubelet_object_id }
  tags                       = local.common.tags
}

# ─── Cross-module permission: app → App Insights ──────────────────────────
# App Insights has local auth disabled, so the app must present an Entra token
# from its workload identity AND hold this role to send telemetry.
resource "azurerm_role_assignment" "app_telemetry" {
  scope                = module.monitoring.application_insights_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = module.aks.app_identity_principal_id
  principal_type       = "ServicePrincipal"
  description          = "App sends OpenTelemetry data to App Insights with its workload identity."
}
