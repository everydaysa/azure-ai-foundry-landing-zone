# ─── AKS module ───────────────────────────────────────────────────────────
#
#  you / CI ──(Entra token; `az aks command invoke`)──▶ API server (PRIVATE IP only)
#                                                        Entra ID + Azure RBAC, local accounts OFF
#  aks-<prefix>
#   ├─ node pool: AzureLinux, D*ds (per env), autoscaled, zones per env, ephemeral OS, host encryption
#   │    CNI Overlay + Cilium (network policy) ── egress ──▶ NAT Gateway (network module)
#   ├─ OIDC issuer ──▶ federated credential ──▶ id-<prefix>-app  (the app's Azure identity)
#   ├─ add-ons: Azure Policy (Gatekeeper/OPA) · Key Vault CSI · Container Insights (MSI auth)
#   └─ kubelet identity ──(AcrPull, granted by the stack)──▶ ACR via Private Endpoint

locals {
  cluster_name = "aks-${var.name_prefix}"
}

# ─── Identities ───────────────────────────────────────────────────────────
# Control-plane identity is created BEFORE the cluster so it can be granted
# Network Contributor on the VNet first (join the node subnet, use the NAT
# Gateway). A system-assigned identity would only exist after creation -
# too late for the subnet permission check.
resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "id-${var.name_prefix}-aks-cp"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "control_plane_network" {
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
  description          = "AKS control plane: join the node subnet and use the NAT Gateway."
}

# The application's own Azure identity (workload identity). Pods using the
# bound ServiceAccount receive Entra tokens for THIS identity - no secrets.
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.name_prefix}-app"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ─── Cluster ──────────────────────────────────────────────────────────────
resource "azurerm_kubernetes_cluster" "this" {
  #checkov:skip=CKV_AZURE_6:Private cluster - the API server has no public endpoint, so authorized IP ranges do not apply.
  #checkov:skip=CKV_AZURE_117:Platform-managed disk encryption + host encryption are used; a customer-managed disk encryption set is the regulated-workload extension (ADR-0007).
  #checkov:skip=CKV_AZURE_170:SKU tier is chosen per environment - Free in dev (cost), Standard in prod. An OPA policy on the plan (Step 13) fails any prod plan that is not Standard.
  #checkov:skip=CKV_AZURE_232:Single node pool to keep dev cost low; production adds a separate user pool and sets only_critical_addons_enabled (ADR-0007).

  name                = local.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = local.cluster_name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier

  # ── API server: private, Entra-only ─────────────────────────────────────
  private_cluster_enabled             = true
  private_dns_zone_id                 = "System" # AKS manages the privatelink.<region>.azmk8s.io zone
  private_cluster_public_fqdn_enabled = false
  run_command_enabled                 = true # enables `az aks command invoke` for CI and operators

  local_account_disabled            = true # no static admin kubeconfig exists
  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    tenant_id          = var.tenant_id
    azure_rbac_enabled = true # Kubernetes authorization via Azure role assignments
  }

  # ── Identity ───────────────────────────────────────────────────────────
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ── Nodes ──────────────────────────────────────────────────────────────
  node_provisioning_profile {
    mode = "Manual" # classic node pools (azurerm v5 requires this block)
  }

  default_node_pool {
    name                        = "system"
    temporary_name_for_rotation = "systemtmp"
    vm_size                     = var.node_vm_size
    vnet_subnet_id              = var.aks_nodes_subnet_id
    zones                       = length(var.availability_zones) > 0 ? var.availability_zones : null

    auto_scaling_enabled = true
    min_count            = var.node_min_count
    max_count            = var.node_max_count
    max_pods             = 110

    os_sku          = "AzureLinux" # minimal, Microsoft-maintained node OS
    os_disk_type    = "Ephemeral"  # OS disk on the VM's local disk: faster, nothing persisted
    os_disk_size_gb = var.node_os_disk_size_gb

    host_encryption_enabled = true  # encrypts temp disk + OS/data disk caches at the host
    node_public_ip_enabled  = false # nodes have no public IPs

    upgrade_settings {
      max_surge = "33%"
    }

    tags = var.tags
  }

  # ── Network ────────────────────────────────────────────────────────────
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay" # pods use a private overlay range, not VNet IPs
    network_data_plane  = "cilium"  # eBPF data plane
    network_policy      = "cilium"  # Kubernetes NetworkPolicy enforcement
    outbound_type       = "userAssignedNATGateway"
    load_balancer_sku   = "standard"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
  }

  # ── Upgrades & hygiene ─────────────────────────────────────────────────
  automatic_upgrade_channel    = "patch"
  node_os_upgrade_channel      = "NodeImage"
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 48

  # ── Add-ons ────────────────────────────────────────────────────────────
  azure_policy_enabled = true # Gatekeeper (OPA) admission control

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true # required: the workspace rejects key-based ingestion
  }

  tags = var.tags

  depends_on = [azurerm_role_assignment.control_plane_network]
}

# ─── Workload identity federation ─────────────────────────────────────────
# "If the cluster's OIDC issuer vouches for ServiceAccount <ns>/<sa>, Entra
#  may issue tokens for id-<prefix>-app." Any other ServiceAccount gets nothing.
resource "azurerm_federated_identity_credential" "app" {
  name                      = "fic-${var.app_namespace}-${var.app_service_account}"
  user_assigned_identity_id = azurerm_user_assigned_identity.app.id
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.app_namespace}:${var.app_service_account}"
  audience                  = ["api://AzureADTokenExchange"]
}

# ─── Container Insights (managed-identity auth) ───────────────────────────
resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "dcr-${local.cluster_name}-ci"
  location            = var.location
  resource_group_name = var.resource_group_name
  description         = "Container Insights for ${local.cluster_name} -> central workspace."

  destinations {
    log_analytics {
      name                  = "central-workspace"
      workspace_resource_id = var.log_analytics_workspace_id
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerInsights-Group-Default"]
    destinations = ["central-workspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = ["Microsoft-ContainerInsights-Group-Default"]
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Off"
          enableContainerLogV2   = true
        }
      })
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id
  description             = "Routes Container Insights data for this cluster through the DCR."
}

# ─── Control-plane logs ───────────────────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "this" {
  name                           = "diag-to-central-workspace"
  target_resource_id             = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  # kube-audit-admin = every WRITE to the API server (create/update/delete,
  # exec, secrets access) with the caller's Entra identity - the security
  # signal - without the very high volume of read-only get/list/watch events.
  enabled_log {
    category = "kube-audit-admin"
  }

  # guard = Entra ID authentication decisions for the API server.
  enabled_log {
    category = "guard"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
