# Offline unit tests (mocked provider - no Azure login, no cost):
#   cd infra/modules/aks && terraform init -backend=false && terraform test

mock_provider "azurerm" {
  # Mocks invent random strings for computed values; resources that validate
  # IDs, UUIDs or URLs need realistic shapes.
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-aifz-test"
      principal_id = "33333333-3333-3333-3333-333333333333"
      client_id    = "44444444-4444-4444-4444-444444444444"
    }
  }

  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.ContainerService/managedClusters/aks-aifz-test"
      oidc_issuer_url     = "https://eastus2.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"
      node_resource_group = "MC_rg-aifz-test_aks-aifz-test_eastus2"
      kubelet_identity = [{
        client_id                 = "55555555-5555-5555-5555-555555555555"
        object_id                 = "66666666-6666-6666-6666-666666666666"
        user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MC_rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aks-agentpool"
      }]
    }
  }

  mock_resource "azurerm_monitor_data_collection_rule" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Insights/dataCollectionRules/dcr-aks-aifz-test-ci"
    }
  }
}

variables {
  name_prefix                = "aifz-test"
  location                   = "eastus2"
  resource_group_name        = "rg-aifz-test"
  tenant_id                  = "00000000-0000-0000-0000-000000000000"
  vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/virtualNetworks/vnet-aifz-test"
  aks_nodes_subnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/virtualNetworks/vnet-aifz-test/subnets/snet-aks-nodes"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.OperationalInsights/workspaces/log-aifz-test"
  sku_tier                   = "Free"
}

run "api_server_is_private_and_entra_only" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.private_cluster_enabled && !azurerm_kubernetes_cluster.this.private_cluster_public_fqdn_enabled
    error_message = "The API server must be private with no public FQDN."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled
    error_message = "Local (static admin) accounts must be disabled."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].azure_rbac_enabled
    error_message = "Kubernetes authorization must use Azure RBAC."
  }
}

run "workload_identity_is_enabled_and_scoped_to_one_service_account" {
  command = apply # mocked

  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled && azurerm_kubernetes_cluster.this.workload_identity_enabled
    error_message = "OIDC issuer and workload identity must be enabled."
  }

  assert {
    condition     = azurerm_federated_identity_credential.app.subject == "system:serviceaccount:ai-app:foundry-app"
    error_message = "The federated credential must trust exactly one ServiceAccount."
  }

  assert {
    condition     = azurerm_federated_identity_credential.app.issuer == azurerm_kubernetes_cluster.this.oidc_issuer_url
    error_message = "The federated credential must trust THIS cluster's OIDC issuer."
  }
}

run "nodes_are_hardened" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].host_encryption_enabled && azurerm_kubernetes_cluster.this.default_node_pool[0].os_disk_type == "Ephemeral"
    error_message = "Nodes must use host encryption and ephemeral OS disks."
  }

  assert {
    condition     = !azurerm_kubernetes_cluster.this.default_node_pool[0].node_public_ip_enabled
    error_message = "Nodes must not have public IPs."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].min_count == 2 && length(azurerm_kubernetes_cluster.this.default_node_pool[0].zones) == 3
    error_message = "Two nodes minimum, spread across three zones."
  }
}

run "network_is_overlay_cilium_with_nat_egress" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_plugin_mode == "overlay" && azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "cilium"
    error_message = "Use Azure CNI Overlay with Cilium network policy."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].outbound_type == "userAssignedNATGateway"
    error_message = "Egress must go through the NAT Gateway."
  }
}

run "policy_and_monitoring_addons" {
  command = apply # mocked

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_policy_enabled
    error_message = "Azure Policy (Gatekeeper) must be enabled."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.oms_agent[0].msi_auth_for_monitoring_enabled
    error_message = "Container Insights must use managed-identity auth (the workspace rejects keys)."
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule_association.container_insights.target_resource_id == azurerm_kubernetes_cluster.this.id
    error_message = "The Container Insights DCR must be associated with the cluster."
  }
}

run "empty_zone_list_means_regional_placement" {
  command = plan

  variables {
    availability_zones = []
  }

  assert {
    condition     = try(length(azurerm_kubernetes_cluster.this.default_node_pool[0].zones), 0) == 0
    error_message = "An empty zone list must produce a regional (non-zonal) node pool."
  }
}

run "rejects_min_greater_than_max" {
  command = plan

  variables {
    node_min_count = 4
    node_max_count = 3
  }

  expect_failures = [var.node_min_count]
}
