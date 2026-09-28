# ADR-0009: Policy as code with Checkov + OPA

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

Security decisions (ADR-0001 to 0008) are only as strong as their weakest future change. Someone will eventually flip a flag "just to debug". Reviewers miss things, and the decisions must hold without relying on memory.

## Decision

1. **Checkov** scans the code (Terraform, Kubernetes YAML, Dockerfile) with one config file, `policy/checkov/.checkov.yaml`. The baseline is broad and generic. Every skip is inline, with a reason tied to an ADR.
2. **OPA (Rego)** encodes *our* architecture rules and evaluates two artifacts:
   - the **Terraform plan JSON**, where values are resolved (a variable default or module wiring can't hide a public endpoint);
   - the **rendered Kubernetes manifests**: exactly what `kubectl apply` receives.
3. **Every rule has unit tests** (`opa test`): a compliant case passes and a violation is denied. Policies are code, so they get tests like code.
4. The same `make` targets run locally, in pre-merge CI (offline: Checkov, `opa test`, rendered-manifest checks) and in the plan workflow (`policy-plan` on the real plan) before anything is applied.
5. **Defense in depth in the cluster:** Pod Security Admission `restricted` and the Azure Policy add-on (Gatekeeper) enforce at admission time. The pipeline catches problems early, and the cluster catches whatever bypasses the pipeline.

## Alternatives considered

| Option | Why not (now) |
|---|---|
| Checkov only | It can't express environment-specific rules (prod Standard tier) or gaps such as App Insights local auth, and custom Checkov Python checks are harder to unit-test |
| Conftest | Good wrapper over OPA; a ~60-line script (`scripts/opa-eval.sh`) avoids another tool dependency |
| Sentinel / Terraform Cloud | Ties policy to a commercial platform; state and runs stay in our own Azure account |
| Azure Policy only | Enforces *after* deployment (or blocks it mid-apply). Shifting left gives the feedback in the PR |

## Consequences

- ✅ Architecture decisions are executable: a PR that re-enables API keys, opens a public endpoint, grants Owner or deploys a mutable image tag fails before review.
- ✅ The Checkov CKV_AZURE_170 skip (AKS Free tier in dev) is compensated by an OPA rule for prod.
- ⚠️ Rules match on attribute names in the azurerm v5 plan schema. A provider major upgrade must re-run `make policy-plan`. A renamed attribute shows up as a **deny** (a missing value is treated as non-compliant), so the failure mode is safe.
