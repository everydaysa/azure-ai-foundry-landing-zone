# Offline unit tests (mocked provider - no Azure login, no cost):
#   cd infra/modules/ai_foundry && terraform init -backend=false && terraform test

mock_provider "azurerm" {
  # Downstream resources validate the account ID's shape, so mock a real-looking one.
  mock_resource "azurerm_cognitive_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.CognitiveServices/accounts/ais-aifz-test-abc1"
    }
  }
}

variables {
  name_prefix                = "aifz-test"
  name_suffix                = "abc1"
  location                   = "eastus2"
  resource_group_name        = "rg-aifz-test"
  private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/virtualNetworks/vnet-aifz-test/subnets/snet-private-endpoints"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.OperationalInsights/workspaces/log-aifz-test"

  private_dns_zone_ids = {
    cognitiveservices = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
    openai            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
    aiservices        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
    keyvault          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }

  model_deployments = {
    chat = {
      model_name    = "gpt-4.1-mini"
      model_version = "2025-04-14"
      sku_name      = "DataZoneStandard"
      capacity      = 10
    }
  }

  openai_user_principal_ids = { app = "11111111-1111-1111-1111-111111111111" }
}

run "no_api_keys_and_no_public_access" {
  command = plan

  assert {
    condition     = azurerm_cognitive_account.this.local_auth_enabled == false
    error_message = "local_auth_enabled must be false - API keys must not work."
  }

  assert {
    condition     = azurerm_cognitive_account.this.public_network_access_enabled == false && azurerm_cognitive_account.this.network_acls[0].default_action == "Deny"
    error_message = "The account must have no public network access."
  }

  assert {
    condition     = azurerm_cognitive_account.this.outbound_network_access_restricted == true
    error_message = "Outbound access must be restricted (data-exfiltration guard)."
  }

  assert {
    condition     = azurerm_cognitive_account.this.kind == "AIServices" && azurerm_cognitive_account.this.project_management_enabled
    error_message = "Must be a Foundry (AIServices) account with projects enabled."
  }

  assert {
    condition     = azurerm_cognitive_account.this.custom_subdomain_name == "ais-aifz-test-abc1"
    error_message = "A custom subdomain is required for Entra auth and Private Endpoints."
  }
}

run "private_endpoint_registers_in_all_three_zones" {
  command = apply # mocked

  assert {
    condition = toset(azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids) == toset([
      var.private_dns_zone_ids["cognitiveservices"],
      var.private_dns_zone_ids["openai"],
      var.private_dns_zone_ids["aiservices"],
    ])
    error_message = "The Foundry PE must register in exactly the three Foundry zones."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].subresource_names == tolist(["account"])
    error_message = "The PE must target the 'account' sub-resource."
  }
}

run "deployments_are_pinned_and_filtered" {
  command = apply # mocked

  assert {
    condition     = azurerm_cognitive_deployment.this["chat"].version_upgrade_option == "OnceCurrentVersionExpired"
    error_message = "Model versions must be pinned until retirement."
  }

  assert {
    condition     = azurerm_cognitive_deployment.this["chat"].rai_policy_name == "Microsoft.DefaultV2"
    error_message = "The default content filter must be applied."
  }

  assert {
    condition     = azurerm_cognitive_deployment.this["chat"].sku[0].name == "DataZoneStandard" && azurerm_cognitive_deployment.this["chat"].sku[0].capacity == 10
    error_message = "SKU and capacity must come from model_deployments."
  }
}

run "workloads_get_inference_only_access" {
  command = apply # mocked

  assert {
    condition     = azurerm_role_assignment.openai_user["app"].role_definition_name == "Cognitive Services OpenAI User"
    error_message = "Workloads get Cognitive Services OpenAI User - inference only."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this.log_analytics_workspace_id == var.log_analytics_workspace_id
    error_message = "Foundry logs must go to the central workspace."
  }
}

run "rejects_missing_foundry_dns_zone" {
  command = plan

  variables {
    private_dns_zone_ids = {
      openai = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
    }
  }

  expect_failures = [var.private_dns_zone_ids]
}

run "rejects_provisioned_sku" {
  command = plan

  variables {
    model_deployments = {
      chat = {
        model_name    = "gpt-4.1-mini"
        model_version = "2025-04-14"
        sku_name      = "ProvisionedManaged"
        capacity      = 10
      }
    }
  }

  expect_failures = [var.model_deployments]
}
