# Runbook

Step-by-step operations for the landing zone. Every command runs from the repository root. `make help` lists all targets.

- [0. Prerequisites](#0-prerequisites)
- [1. First-time setup](#1-first-time-setup-from-an-empty-subscription)
- [2. Everyday change](#2-everyday-change-the-normal-path)
- [3. Deploy prod](#3-deploy-prod)
- [4. Verify an environment](#4-verify-an-environment)
- [5. Roll back](#5-roll-back)
- [6. Drift and policy findings](#6-drift-and-policy-findings)
- [7. Credential rotation](#7-credential-rotation)
- [8. Teardown](#8-teardown-in-order)
- [9. Troubleshooting: errors we actually hit](#9-troubleshooting-errors-we-actually-hit)

---

## 0. Prerequisites

| Tool | Version used | Check |
|---|---|---|
| Terraform | 1.16.0 | `terraform version` |
| Azure CLI | 2.7x+ | `az version` |
| GitHub CLI | 2.x | `gh auth status` (logged in as the repo admin) |
| Docker (buildx) | Desktop 4.x | `docker buildx version` |
| kubectl | 1.3x | `kubectl version --client` |
| OPA | 1.21.0 | `opa version` |
| Checkov | 3.3.x | `checkov --version` |
| tflint · pre-commit | 0.64 · 4.x | `make hooks` installs the git hooks |

Azure: `az login` as a user with **Owner** on the subscription (bootstrap only).

### Quota and capacity pre-checks (do these BEFORE the first apply)

```bash
# 1. vCPU quota for the node VM family (need ≥ nodes × 2 vCPU, plus headroom for upgrades)
az vm list-usage -l eastus2 -o table --query "[?contains(name.value,'DDSv4') || contains(name.value,'DDSv5') || name.value=='cores'].{family:name.localizedValue, used:currentValue, limit:limit}"

# 2. Does AKS accept zonal placement for this subscription?
az vm list-skus -l eastus2 --size Standard_D2ds_v4 --query "[0].{zones:locationInfo[0].zones, restrictions:restrictions}" -o json

# 3. Model availability and quota
az cognitiveservices usage list -l eastus2 -o table --query "[?contains(name.value,'gpt-5.4-mini')]"

# 4. Host encryption feature (required by the node pool)
az feature show --namespace Microsoft.Compute --name EncryptionAtHost --query properties.state -o tsv   # Registered
```

`make preflight` runs the login, host encryption and state-account checks.

---

## 1. First-time setup (from an empty subscription)

```bash
# 1. Bootstrap: state storage, GitHub identities + federated credentials, env resource groups
#    (set github_owner/repo and their numeric IDs in infra/bootstrap/terraform.tfvars first:
#     gh api repos/<owner>/<repo> --jq '"\(.owner.id) \(.id)"')
make bootstrap

# 2. GitHub variables (IDs only, no secrets): paste the commands it prints
terraform -chdir=infra/bootstrap output -raw github_setup_commands

# 3. Repository guardrails: environments (main only, prod reviewer) + ruleset on main
scripts/github-settings.sh

# 4. First environment deploy (from your machine, or merge to main and let deploy-dev do it)
make plan ENV=dev && make policy-plan ENV=dev && make apply ENV=dev
make deploy-app ENV=dev
make smoke-test ENV=dev
```

A dev deploy takes about 15–20 minutes, mostly AKS creation.

---

## 2. Everyday change (the normal path)

```bash
git switch -c feat/my-change
# … edit …
make ci                                   # the same checks CI runs (fmt, validate, test, lint, policy, app)
git commit -am "feat: …" && git push -u origin feat/my-change
gh pr create --fill
gh pr checks --watch                      # 7 required checks; the plan is posted as a PR comment
gh pr merge --squash --delete-branch      # → deploy-dev runs automatically
gh run watch $(gh run list --workflow deploy-dev.yml -L1 --json databaseId -q '.[0].databaseId') --exit-status
```

`main` accepts no direct pushes. Every change goes through this path.

## 3. Deploy prod

```bash
gh workflow run deploy-prod.yml --ref main
```

1. The **plan** job runs with the read-only identity. Open the run and read the plan in the job summary; note the **fingerprint**.
2. Approve the **prod** environment in the GitHub UI (*Review deployments*) only if the plan is what you expect.
3. The **deploy** job re-plans and **refuses** if the fingerprint changed, then runs OPA → apply → app deploy → smoke test.

⚠️ Prod costs significantly more than dev (Standard tier, 3+ zonal nodes, 30K TPM). Check quota first (section 0). In the subscription used to build this project, the **regional vCPU limit is 10**. Prod's 3–5 × 2-vCPU nodes plus an upgrade surge node need up to 12, so request a quota increase before the first prod apply.

---

## 4. Verify an environment

```bash
make smoke-test ENV=dev          # /healthz /readyz /whoami /chat from inside the cluster
make policy-k8s ENV=dev          # rendered manifests comply
make plan ENV=dev && make policy-plan ENV=dev   # live infra matches the code and complies
make output ENV=dev              # endpoints and names (no secrets in outputs)
```

Proof points for a review or demo:

```bash
RG=rg-aifz-dev
az cognitiveservices account list -g $RG --query "[].{name:name, localAuthDisabled:properties.disableLocalAuth, public:properties.publicNetworkAccess}" -o table
az aks show -g $RG -n aks-aifz-dev --query "{private:apiServerAccessProfile.enablePrivateCluster, localAccountsDisabled:disableLocalAccounts, workloadIdentity:securityProfile.workloadIdentity.enabled}" -o table
```

---

## 5. Roll back

| What broke | Roll back by |
|---|---|
| App release | Revert the commit on a branch → PR → merge. `deploy-dev` redeploys the previous code as a new digest. For an immediate fix: `az aks command invoke -g rg-aifz-dev -n aks-aifz-dev --command "kubectl -n ai-app rollout undo deployment/aifz-app"` |
| Infrastructure change | Revert the commit → PR (the plan shows the reverse change) → merge |
| Terraform state | The state container is versioned: restore the previous blob version of `<env>.tfstate` in the portal (*Versions*), then `make plan` to confirm |
| Deleted Key Vault | Soft delete + purge protection: `az keyvault recover -n <name>` (7 days dev / 90 prod) |

## 6. Drift and policy findings

`drift.yml` runs nightly and opens **"Drift detected: <env>"** when Azure differs from the code or the live environment violates policy.

1. Read the plan in the issue: what changed, and on which resource?
2. **Unintended change:** revert it by re-applying the code (`gh workflow run deploy-dev.yml`) or fixing it in the portal.
3. **Intended change:** codify it in Terraform → PR → merge.
4. The next run closes the issue automatically.

Who made the change?
```kusto
AzureActivity | where TimeGenerated > ago(2d) and ResourceGroup =~ "rg-aifz-dev" and OperationNameValue endswith "write"
| project TimeGenerated, Caller, OperationNameValue, _ResourceId
```
(`AzureActivity` needs a subscription diagnostic setting sending the Activity Log to the workspace. Without it, use *Activity log* in the portal.)

## 7. Credential rotation

**Nothing needs routine rotation.** No key, client secret or password is used; tokens are issued per request and expire within about an hour.

**One exception: inert keys.** Azure always generates account keys for Foundry (and storage). With local auth disabled they can't authenticate, but anyone with `listKeys` (Owner/Contributor) can read them. If they're ever displayed or shared, regenerate both. If local auth were re-enabled by mistake, a leaked key would work immediately:

```bash
AI=$(az cognitiveservices account list -g rg-aifz-dev --query "[0].name" -o tsv)
for k in key1 key2; do az cognitiveservices account keys regenerate -g rg-aifz-dev -n "$AI" --key-name $k -o none; done
```

What does need periodic attention:
- **Model version retirement:** gpt-5.4-mini `2026-03-17` retires around Sep 2027. Update `model_version` in the tfvars via PR.
- **Kubernetes version:** follow the AKS support calendar; upgrade via `kubernetes_version`.
- **Pinned tool and action versions:** bump SHAs and versions via PR; CI proves they still work.

## 8. Teardown (in order)

```bash
# 1. Stop the nightly drift job (otherwise it reports "everything missing" every night)
gh workflow disable drift.yml

# 2. Destroy the environment (asks you to type the env name)
make destroy ENV=dev

# 3. Confirm nothing billable remains
az resource list -g rg-aifz-dev -o table
az cognitiveservices account list-deleted -o table     # purged on destroy (provider setting)
```

The bootstrap (state storage, identities, resource groups) costs cents per month and is protected by `prevent_destroy` and a `CanNotDelete` lock. To remove it completely:

```bash
az lock delete -g rg-aifz-bootstrap -n <lock-name>          # az lock list -g rg-aifz-bootstrap
# set prevent_destroy = false on the storage account + container in infra/bootstrap/main.tf
terraform -chdir=infra/bootstrap destroy
```

Key Vault names stay reserved during the soft-delete window (purge protection is on by design), so a redeploy within that window gets a new random suffix.

## 9. Troubleshooting: errors we actually hit

| Symptom | Cause | Fix |
|---|---|---|
| `AADSTS700213: No matching federated identity record found for presented assertion subject 'repo:owner@123/repo@456:…'` | GitHub issues **immutable-ID** OIDC subjects for this repo; the federated credential used `owner/repo` | Set `github_owner_id` / `github_repo_id` in bootstrap tfvars → apply (Entra may take a minute) |
| `AvailabilityZoneNotSupported … supported zones are ''` | Subscription has no AKS zonal capacity in the region, even though `list-skus` shows zones | Per-env `aks_availability_zones = []` (dev); keep zones in prod once capacity is confirmed |
| `ErrCode_InsufficientVCPUQuota` | 0 vCPU quota for the chosen family (DDSv5) | Pre-check quota; switch family (D2ds_v4) or request a quota increase |
| `PermissionDenied` calling the model as subscription Owner | Control plane ≠ data plane: Owner has no inference role | Expected. Only the app identity holds *Cognitive Services OpenAI User* |
| `401` calling Foundry with curl | Keys are disabled | Expected. Use an Entra token from an identity with the data-plane role, from inside the VNet |
| `/readyz` returns 503 locally in Docker | No workload identity outside AKS | Expected. Readiness means "can get an Entra token" |
| Checkov CKV_K8S_43 / OPA K1 on the smoke-test Job | Image referenced by tag | Pin by digest: `docker buildx imagetools inspect <image:tag>` |
| gitleaks `generic-api-key` on `rbac.rego` | Built-in role GUIDs look like keys | Line-level `# gitleaks:allow` with a reason (public IDs, same in every tenant) |
| Deploy hangs at "waiting for registry" | JIT IP rule not yet effective | The script retries for 150 s; if your egress IP changes mid-run (VPN), re-run |
| `AppTraces` has rows but `AppRequests` is empty | The distro patches the `fastapi.FastAPI` class, but `main.py` imported it before the patch, so the app instance was never instrumented | Instrument the instance explicitly: `FastAPIInstrumentor.instrument_app(app)` (`app/src/app/telemetry.py`), covered by a regression test |
| `az cognitiveservices account keys list` returns two keys | `disableLocalAuth` makes keys **unusable, not absent**. Azure always generates them, and control-plane roles can list them | Not a breach while local auth is off. If they were displayed or shared, regenerate both (section 7) |
| `make: No rule to make target` | Not run from the repo root | `cd` to the repository root |
| `Error acquiring the state lock` | Another plan/apply holds the lease | Wait (CI uses `-lock-timeout`), or `terraform force-unlock <ID>` only if the holder is dead |
