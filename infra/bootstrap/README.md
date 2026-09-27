# Bootstrap: remote state + GitHub OIDC identities

This runs **once**, from an operator's machine, as a subscription **Owner**. It creates everything the pipelines need before the pipelines can run.

```
rg-aifz-bootstrap
├── staifztfstate<rand>        Storage account: Entra-only (shared keys OFF), TLS 1.2,
│   └── tfstate/               versioning + change feed + 30-day soft delete, CanNotDelete lock
│       ├── dev.tfstate
│       └── prod.tfstate
├── id-aifz-gh-plan            ◀── repo:<owner>/<repo>:pull_request
│                              ◀── repo:<owner>/<repo>:ref:refs/heads/main
├── id-aifz-gh-dev             ◀── repo:<owner>/<repo>:environment:dev
└── id-aifz-gh-prod            ◀── repo:<owner>/<repo>:environment:prod

rg-aifz-dev    ← gh-dev may deploy here only
rg-aifz-prod   ← gh-prod may deploy here only (GitHub environment requires approval)
```

## Security decisions

| Decision | Why |
|---|---|
| **User-assigned managed identities + federated credentials** for CI | No client secrets in GitHub, and nothing to rotate. The identities are plain Azure resources, so no tenant-wide app-registration rights are needed. |
| **One identity per environment**, scoped to **one resource group** | A compromised dev pipeline has zero permissions on prod. |
| **Plan identity is read-only** (`Reader`) | Pull requests from any branch can show a plan but can never change infrastructure. |
| **ABAC-constrained RBAC Administrator** instead of Owner / User Access Administrator | CI can assign only allow-listed roles (`AcrPull`, `Cognitive Services OpenAI User`, …), and only to service principals and managed identities. It can never grant Owner, never grant itself more, and never grant a human. |
| **Shared keys disabled on state** (`use_azuread_auth = true` in backends) | State is readable only with an Entra token, and every access is attributable to an identity. |
| **Resource providers registered here** | azurerm v5 registers none by default, and RG-scoped CI identities cannot register them. |

Accepted trade-offs are recorded in [ADR-0002](../../docs/adr/0002-terraform-state-and-bootstrap.md).

## Run it

```bash
az login
az account set --subscription "<your subscription id>"
cd infra/bootstrap
terraform init
terraform plan -out=tfplan      # review: ~30 resources
terraform apply tfplan
```

Then configure GitHub (needs `gh auth login` with admin on the repo):

```bash
terraform output -raw github_setup_commands | bash
```

## Verify

```bash
terraform output state_backend
terraform output federated_subjects
az role assignment list --all --assignee "$(terraform output -json github_identity_client_ids | jq -r .dev)" \
  --query "[].{role:roleDefinitionName, scope:scope, condition:condition!=null}" -o table
```

The last command should show four roles, all scoped to `rg-aifz-dev`, with `condition = True` on *Role Based Access Control Administrator*.

## Teardown (last, after every environment is destroyed)

State is protected twice, on purpose:

| Guard | Stops |
|---|---|
| `lifecycle { prevent_destroy = true }` on the state account + container | `terraform destroy` / a plan that would replace them |
| `CanNotDelete` management lock | Deletes from the portal, CLI or any other tool |

To tear down deliberately:

```bash
# 1. In main.tf, change BOTH `prevent_destroy = true` lines to false
# 2. Then:
terraform destroy    # removes the lock, then everything above
```

> The bootstrap state file (`terraform.tfstate` in this folder) is git-ignored. Keep it until teardown, or migrate it into the storage account it created by adding an `azurerm` backend block and running `terraform init -migrate-state`.
