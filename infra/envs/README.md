# Environments

Each folder is a thin root module that calls [`../stack`](../stack) with its own `terraform.tfvars`. The structure is identical everywhere; only the values differ.

| Setting | dev | prod |
|---|---|---|
| VNet | `10.10.0.0/16` | `10.20.0.0/16` |
| Log retention / daily cap | 30 days / 2 GB (sized from measured volume) | 90 days / unlimited |
| Key Vault soft-delete | 7 days | 90 days |
| AKS tier / nodes | Free / 2–3 | Standard (SLA) / 3–5 |
| Model | gpt-5.4-mini, DataZoneStandard, 10K TPM | same, 30K TPM |
| Log Analytics on destroy | purged (clean teardown) | kept 14 days (recoverable) |
| State file | `dev.tfstate` | `prod.tfstate` |

## Files

| File | Purpose |
|---|---|
| `versions.tf` | Provider pins + an empty `backend "azurerm" {}` (partial configuration) |
| `backend.hcl` | Non-secret backend values: resource group, container, state key, `use_azuread_auth = true` |
| `providers.tf` | Entra-only storage access; safe destroy behavior for Key Vault, Foundry and Log Analytics |
| `main.tf` | `module "stack"`, the only resource block |
| `variables.tf` / `outputs.tf` | Identical in every environment |
| `terraform.tfvars` | **The only file that differs** |

## Deploy (from a laptop)

```bash
az login
make preflight ENV=dev      # checks login, EncryptionAtHost, state account
make plan ENV=dev           # init against remote state + plan → tfplan
make apply ENV=dev          # applies exactly the reviewed plan
make output ENV=dev         # endpoints, names, identities (no secrets)
make destroy ENV=dev        # asks you to type the env name
```

`make init` passes the state storage account name at init time (`-backend-config="storage_account_name=…"`). Locally the Makefile discovers it with the Azure CLI, and in CI it comes from the `TFSTATE_STORAGE_ACCOUNT` repository variable. So the repository never hard-codes it.

## Why the environment resource groups come from the bootstrap

The stack **reads** `rg-aifz-<env>` with a data source instead of creating it. Each CI deploy identity is scoped to exactly one resource group, so the dev pipeline has no permissions at all in prod. The data source also makes `plan` fail fast if the bootstrap hasn't run.
