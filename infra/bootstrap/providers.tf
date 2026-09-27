provider "azurerm" {
  # Shared keys are disabled on the state account, so any data-plane call
  # must use an Entra ID token instead of a storage account key.
  storage_use_azuread = true

  # azurerm v5 registers NO resource providers by default. The bootstrap runs
  # once as the subscription Owner, so it registers everything the landing
  # zone needs. The CI identities are scoped to resource groups and could not
  # register providers themselves (a subscription-level action).
  resource_providers_to_register = [
    "Microsoft.AlertsManagement",
    "Microsoft.CognitiveServices",
    "Microsoft.ContainerRegistry",
    "Microsoft.ContainerService",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.OperationsManagement",
    "Microsoft.Storage",
  ]

  features {}
}
