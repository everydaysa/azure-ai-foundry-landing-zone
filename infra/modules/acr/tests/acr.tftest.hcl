# Offline unit tests (mocked provider - no Azure login, no cost):
#   cd infra/modules/acr && terraform init -backend=false && terraform test

mock_provider "azurerm" {
  mock_resource "azurerm_container_registry" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.ContainerRegistry/registries/acraifztestabc1"
    }
  }
}

variables {
  name_prefix                = "aifz-test"
  name_suffix                = "abc1"
  location                   = "eastus2"
  resource_group_name        = "rg-aifz-test"
  private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/virtualNetworks/vnet-aifz-test/subnets/snet-private-endpoints"
  private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.OperationalInsights/workspaces/log-aifz-test"
  acr_pull_principal_ids     = { aks_kubelet = "22222222-2222-2222-2222-222222222222" }
}

run "registry_name_is_alphanumeric" {
  command = plan

  assert {
    condition     = azurerm_container_registry.this.name == "acraifztestabc1"
    error_message = "Registry names must be alphanumeric - hyphens from the prefix must be stripped."
  }
}

run "identity_only_access" {
  command = plan

  assert {
    condition     = !azurerm_container_registry.this.admin_enabled && !azurerm_container_registry.this.anonymous_pull_enabled
    error_message = "Admin user and anonymous pull must both be disabled."
  }

  assert {
    condition     = azurerm_container_registry.this.sku == "Premium"
    error_message = "Premium is required for Private Endpoints."
  }
}

run "firewall_is_deny_by_default_with_no_standing_rules" {
  command = plan

  assert {
    condition     = azurerm_container_registry.this.network_rule_set[0].default_action == "Deny"
    error_message = "The registry firewall must deny by default."
  }

  assert {
    # An unset nested block is null (not an empty list) at plan time, so treat
    # "null" and "empty" the same: both mean zero standing IP rules.
    condition     = try(length(azurerm_container_registry.this.network_rule_set[0].ip_rule), 0) == 0
    error_message = "No standing IP rules - CI opens access just-in-time only."
  }

  assert {
    condition     = azurerm_container_registry.this.network_rule_bypass_option == "None"
    error_message = "No trusted-service bypass."
  }
}

run "private_endpoint_and_logging" {
  command = apply # mocked

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].subresource_names == tolist(["registry"])
    error_message = "The PE must target the 'registry' sub-resource."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids == tolist([var.private_dns_zone_id])
    error_message = "The PE must register in privatelink.azurecr.io."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this.log_analytics_workspace_id == var.log_analytics_workspace_id
    error_message = "Registry events must go to the central workspace."
  }

  assert {
    condition     = azurerm_role_assignment.acr_pull["aks_kubelet"].role_definition_name == "AcrPull"
    error_message = "Consumers get AcrPull only."
  }
}
