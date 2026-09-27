output "tenant_id" {
  description = "Entra tenant ID (GitHub variable AZURE_TENANT_ID)."
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Subscription ID (GitHub variable AZURE_SUBSCRIPTION_ID)."
  value       = data.azurerm_client_config.current.subscription_id
}

output "state_backend" {
  description = "Values for the azurerm backend in infra/envs/<env>/backend.hcl."
  value = {
    resource_group_name  = azurerm_resource_group.bootstrap.name
    storage_account_name = azurerm_storage_account.tfstate.name
    container_name       = azurerm_storage_container.tfstate.name
  }
}

output "environment_resource_groups" {
  description = "Resource group each environment deploys into."
  value       = { for k, rg in azurerm_resource_group.env : k => rg.name }
}

output "github_identity_client_ids" {
  description = "Client IDs GitHub Actions passes to azure/login (not secrets)."
  value       = { for k, id in azurerm_user_assigned_identity.github : k => id.client_id }
}

output "federated_subjects" {
  description = "Exact OIDC subjects Entra ID will accept - useful when debugging AADSTS700213."
  value       = { for k, fc in azurerm_federated_identity_credential.github : k => fc.subject }
}

output "github_setup_commands" {
  description = "Run these once (gh CLI) to create GitHub environments and variables."
  value       = <<-EOT
    REPO=${local.repo_full_name}

    # Repository-wide variables (IDs are identifiers, not secrets)
    gh variable set AZURE_TENANT_ID       -R $REPO --body ${data.azurerm_client_config.current.tenant_id}
    gh variable set AZURE_SUBSCRIPTION_ID -R $REPO --body ${data.azurerm_client_config.current.subscription_id}
    gh variable set AZURE_PLAN_CLIENT_ID  -R $REPO --body ${azurerm_user_assigned_identity.github["plan"].client_id}
    gh variable set TFSTATE_RESOURCE_GROUP  -R $REPO --body ${azurerm_resource_group.bootstrap.name}
    gh variable set TFSTATE_STORAGE_ACCOUNT -R $REPO --body ${azurerm_storage_account.tfstate.name}
    %{for env in sort(tolist(var.environments))}
    # ${env} environment + its deploy identity
    gh api -X PUT repos/$REPO/environments/${env} >/dev/null
    gh variable set AZURE_CLIENT_ID -R $REPO --env ${env} --body ${azurerm_user_assigned_identity.github[env].client_id}
    %{endfor}
  EOT
}
