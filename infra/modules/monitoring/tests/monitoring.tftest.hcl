# Offline unit tests (mocked provider - no Azure login, no cost):
#   cd infra/modules/monitoring && terraform init -backend=false && terraform test

mock_provider "azurerm" {
  # A mocked provider invents random strings for computed attributes such as
  # `id`. App Insights validates that `workspace_id` is a real ARM resource ID,
  # so give the mocked workspace a correctly shaped one.
  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aifz-test/providers/Microsoft.OperationalInsights/workspaces/log-aifz-test"
    }
  }
}

variables {
  name_prefix         = "aifz-test"
  location            = "eastus2"
  resource_group_name = "rg-aifz-test"
}

run "entra_only_auth_everywhere" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.local_authentication_enabled == false
    error_message = "Workspace must reject shared-key auth."
  }

  assert {
    condition     = azurerm_application_insights.this.local_authentication_enabled == false
    error_message = "App Insights must reject instrumentation-key-only ingestion."
  }
}

run "app_insights_is_workspace_based" {
  command = apply # mocked: resolves the workspace ID so the link can be checked

  assert {
    condition     = azurerm_application_insights.this.workspace_id == azurerm_log_analytics_workspace.this.id
    error_message = "App Insights must store its data in the central workspace."
  }
}

run "dev_profile_caps_ingestion" {
  command = plan

  variables {
    retention_in_days = 30
    daily_quota_gb    = 1
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.daily_quota_gb == 1 && azurerm_application_insights.this.daily_data_cap_in_gb == 1
    error_message = "The dev cap must apply to both the workspace and App Insights."
  }
}

run "prod_profile_is_uncapped" {
  command = plan

  variables {
    retention_in_days = 90
    daily_quota_gb    = -1
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 90 && azurerm_log_analytics_workspace.this.daily_quota_gb == -1
    error_message = "Prod keeps 90 days and never drops logs."
  }
}

run "rejects_retention_below_30_days" {
  command = plan

  variables {
    retention_in_days = 7
  }

  expect_failures = [var.retention_in_days]
}
