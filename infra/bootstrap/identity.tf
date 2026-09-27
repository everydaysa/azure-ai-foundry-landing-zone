# ─── GitHub Actions identities (OIDC, no secrets) ─────────────────────────
#
#   pull_request / main  ──▶ id-<project>-gh-plan   read-only + state lock
#   environment: dev     ──▶ id-<project>-gh-dev    deploys rg-<project>-dev
#   environment: prod    ──▶ id-<project>-gh-prod   deploys rg-<project>-prod
#
# GitHub signs a short-lived JWT for each workflow run. Entra ID only swaps it
# for an Azure token when issuer + subject + audience match a credential below
# EXACTLY, so the subject string is the security boundary.

locals {
  github_issuer   = "https://token.actions.githubusercontent.com"
  github_audience = "api://AzureADTokenExchange"

  ci_identities = merge(
    { plan = "Read-only plans for pull requests and drift detection on main" },
    { for env in var.environments : env => "Deploys the ${env} environment" }
  )

  federated_credentials = merge(
    {
      plan-pull-request = {
        identity = "plan"
        subject  = "repo:${local.repo_full_name}:pull_request"
      }
      plan-main-branch = {
        identity = "plan"
        subject  = "repo:${local.repo_full_name}:ref:refs/heads/main"
      }
    },
    {
      for env in var.environments : "${env}-environment" => {
        identity = env
        subject  = "repo:${local.repo_full_name}:environment:${env}"
      }
    }
  )
}

resource "azurerm_user_assigned_identity" "github" {
  for_each = local.ci_identities

  name                = "id-${var.project}-gh-${each.key}"
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = azurerm_resource_group.bootstrap.location
  tags                = merge(local.tags, { purpose = each.value })
}

resource "azurerm_federated_identity_credential" "github" {
  for_each = local.federated_credentials

  name                      = "gh-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.github[each.value.identity].id
  issuer                    = local.github_issuer
  audience                  = [local.github_audience]
  subject                   = each.value.subject
}
