# Offline unit tests (mocked provider - no Azure login, no cost):
#   cd infra/modules/key_vault && terraform init -backend=false && terraform test

mock_provider "azurerm" {
  # Downstream resources validate the vault ID's shape, so mock a real-looking one.
  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.KeyVault/vaults/kv-aifz-test-abc1"
      vault_uri = "https://kv-aifz-test-abc1.vault.azure.net/"
    }
  }
}

variables {
  name_prefix                = "aifz-test"
  name_suffix                = "abc1"
  location                   = "eastus2"
  resource_group_name        = "rg-aifz-test"
  tenant_id                  = "00000000-0000-0000-0000-000000000000"
  soft_delete_retention_days = 7
  private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/virtualNetworks/vnet-aifz-test/subnets/snet-private-endpoints"
  private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.OperationalInsights/workspaces/log-aifz-test"
  secrets_user_principal_ids = { app = "11111111-1111-1111-1111-111111111111" }
}

run "vault_is_locked_down" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled && !azurerm_key_vault.this.public_network_access_enabled
    error_message = "Vault must use RBAC and have public network access disabled."
  }

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled && azurerm_key_vault.this.soft_delete_retention_days == 7
    error_message = "Purge protection must be on with the requested retention."
  }

  assert {
    condition     = azurerm_key_vault.this.network_acls[0].default_action == "Deny" && azurerm_key_vault.this.network_acls[0].bypass == "None"
    error_message = "Network ACLs must deny by default with no trusted-service bypass."
  }

  assert {
    condition     = length(azurerm_key_vault.this.name) <= 24
    error_message = "Key Vault names are limited to 24 characters."
  }
}

run "private_endpoint_wired_to_dns_and_subnet" {
  command = apply # mocked

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].subresource_names == tolist(["vault"])
    error_message = "The PE must target the 'vault' sub-resource."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids == tolist([var.private_dns_zone_id])
    error_message = "The PE must register its A record in the vaultcore privatelink zone."
  }

  assert {
    condition     = azurerm_private_endpoint.this.subnet_id == var.private_endpoint_subnet_id
    error_message = "The PE must live in the Private Endpoint subnet."
  }
}

run "audit_logs_go_to_central_workspace" {
  command = apply # mocked

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this.log_analytics_workspace_id == var.log_analytics_workspace_id
    error_message = "Diagnostics must target the central workspace."
  }

  assert {
    condition     = anytrue([for l in azurerm_monitor_diagnostic_setting.this.enabled_log : l.category_group == "allLogs"])
    error_message = "allLogs (includes AuditEvent) must be enabled."
  }
}

run "workloads_get_read_only_secret_access" {
  command = apply # mocked

  assert {
    condition     = azurerm_role_assignment.secrets_user["app"].role_definition_name == "Key Vault Secrets User"
    error_message = "Workloads get Key Vault Secrets User - read, never write."
  }
}

run "rejects_retention_outside_7_to_90" {
  command = plan

  variables {
    soft_delete_retention_days = 3
  }

  expect_failures = [var.soft_delete_retention_days]
}
