# ADR-0001: Keyless identity everywhere (OIDC federation + managed identities)

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

AI platforms usually leak through credentials: model API keys in app settings, service-principal secrets in CI, and storage keys in Terraform backends. Every stored secret needs rotation, can be exfiltrated, and cannot be attributed to a specific workload.

## Decision

1. **CI → Azure:** GitHub Actions authenticate with **OIDC federated credentials** on **user-assigned managed identities**. The token's `subject` claim pins each identity to one trigger:
   - `pull_request` or `ref:refs/heads/main` → plan identity (Reader)
   - `environment:dev` → dev deploy identity (rg-aifz-dev only)
   - `environment:prod` → prod deploy identity (rg-aifz-prod only, behind a GitHub environment approval)
2. **App → AI Foundry:** the AKS workload uses **Workload Identity**: the cluster's OIDC issuer, a federated credential, and a Kubernetes ServiceAccount. Foundry has `local_auth_enabled = false`, so API keys do not exist.
3. **Terraform → state:** the state account has `shared_access_key_enabled = false`, and backends use `use_azuread_auth = true`.
4. **Privilege escalation guard:** deploy identities get *Role Based Access Control Administrator* with an **ABAC condition**. They may assign only an allow-list of data-plane roles, and only to service principals.

## Consequences

- ✅ No secrets to store, rotate or leak in GitHub, Kubernetes or Terraform.
- ✅ Every call is attributable to a named identity in Entra sign-in logs and Azure activity logs.
- ✅ Blast radius per environment is one resource group.
- ⚠️ The OIDC subject must match exactly. Renaming the repo or org, or customising the org's OIDC subject template, requires updating the federated credentials.
- ⚠️ Adding a new role assignment to the stack means adding the role to `pipeline_assignable_roles` and re-running the bootstrap as Owner. This is deliberate friction.
