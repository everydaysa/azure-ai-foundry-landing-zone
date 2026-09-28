# Azure AI Foundry Secure Landing Zone

[![ci](https://github.com/everydaysa/azure-ai-foundry-landing-zone/actions/workflows/ci.yml/badge.svg)](https://github.com/everydaysa/azure-ai-foundry-landing-zone/actions/workflows/ci.yml)
[![deploy-dev](https://github.com/everydaysa/azure-ai-foundry-landing-zone/actions/workflows/deploy-dev.yml/badge.svg)](https://github.com/everydaysa/azure-ai-foundry-landing-zone/actions/workflows/deploy-dev.yml)
[![drift](https://github.com/everydaysa/azure-ai-foundry-landing-zone/actions/workflows/drift.yml/badge.svg)](https://github.com/everydaysa/azure-ai-foundry-landing-zone/actions/workflows/drift.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A production-grade, security-first foundation for running AI workloads on Azure, deployable end to end from this repository.

> **Model API keys disabled. Zero public PaaS endpoints. Zero pipeline secrets. One place for all telemetry.**

`Terraform (7 modules, dev/prod)` · `Azure AI Foundry` · `AKS` · `FastAPI` · `OpenTelemetry` · `Checkov` · `OPA` · `GitHub Actions`

---

## What it does

An AKS-hosted FastAPI service calls a **gpt-5.4-mini** deployment in **Azure AI Foundry**:

- **without an API key:** Foundry local auth is disabled, so even its platform-generated keys can't authenticate; the app uses **AKS workload identity**.
- **without any public endpoint:** Foundry, Key Vault and ACR are reached through **Private Endpoints + Private DNS**; the AKS API server is private.
- **deployed by a pipeline that holds no secrets:** GitHub Actions logs in with **OIDC**, a PR can only *read* Azure, and every deploy passes **Checkov + OPA** gates.
- **observed in one place:** app, cluster, audit, model, vault and registry signals all land in **one Log Analytics workspace** that accepts only Entra-authenticated writes.

## Architecture

![Reference architecture: GitHub Actions, Entra ID, the private AKS cluster, Private Endpoints to AI Foundry, Key Vault and ACR, and one Log Analytics workspace](docs/images/architecture.svg)

The numbered flows: ① GitHub presents an OIDC token → ② the deploy identity plans, checks policy and applies, pushes the image just-in-time, and runs kubectl through ARM → ③ state is locked with an Entra token → ④ the pod swaps its service-account token for an Entra token → ⑤ the app reaches Foundry through a Private Endpoint → ⑥ nodes pull the image by digest over the registry's Private Endpoint → ⑦ the only outbound path is the NAT Gateway on 443 → ⑧ every signal lands in one workspace.

**➜ [docs/architecture.md](docs/architecture.md)** connects everything: the full system picture, the four journeys (a request, a change, the nightly audit, a build from scratch), every identity and what it can do, every network path, and where each control is enforced.

## Security claims and where each is enforced

| Claim | Enforced by (code) | Verified by |
|---|---|---|
| No model API keys | `ai_foundry`: `local_auth_enabled = false` | Checkov · OPA T1 · runtime: keys rejected |
| No public PaaS endpoints | `public_network_access_enabled = false` + Private Endpoints/DNS | Checkov · OPA T4 · DNS resolves to 10.10.4.x only in-cluster |
| App is keyless | AKS workload identity + federated credential for one service account | Smoke test `/whoami` → `workload_identity` |
| Pipeline is keyless and least-privilege | OIDC federated credentials; Reader for PRs; per-env deploy identities; ABAC-limited RBAC admin | OPA T8 · environments main-only · prod reviewer |
| Telemetry can't be forged | Log Analytics + App Insights local auth off | OPA T2 (no Checkov check exists) |
| Hardened workloads | PSA `restricted`, non-root, read-only FS, digest-pinned images, default-deny network, IMDS blocked | Checkov · OPA K1–K6 · API server admission |
| Drift is caught | Nightly plan + OPA on the live environment | `drift.yml` opens/closes an issue |

Threat model and blast-radius analysis: **[docs/security.md](docs/security.md)**.

## Pipeline

```
PR ───────▶ ci.yml        fmt · validate · 38 module tests · tflint · Checkov · 43 OPA tests · pytest · gitleaks · actionlint
     └────▶ plan.yml      read-only OIDC → plan dev + prod → OPA on the plan → PR comment
merge ────▶ deploy-dev    plan → OPA → apply → build → JIT push → OPA on manifests → deploy by digest → smoke test
manual ───▶ deploy-prod   plan → ⏸ reviewer approves fingerprint → re-plan must match → apply → deploy → smoke test
nightly ──▶ drift.yml     live plan + OPA → "Drift detected" issue (auto-closes when clean)
```

## Quick start

```bash
make help                      # every command, with a description
make ci                        # all local checks (no Azure needed)

# deploy (Azure Owner once for the bootstrap; see docs/runbook.md)
make bootstrap
make plan ENV=dev && make policy-plan ENV=dev && make apply ENV=dev
make deploy-app ENV=dev
make smoke-test ENV=dev
make ask ENV=dev PROMPT="Explain a private endpoint in one sentence."
make security-test ENV=dev     # PASS/FAIL for every security control, from outside and inside the cluster
make destroy ENV=dev           # tear down (dev costs ≈ $9–11/day while running)
```

## Repository map

```
infra/
  bootstrap/          one-time: state storage, GitHub OIDC identities, env resource groups
  modules/            network · monitoring · private_dns · key_vault · ai_foundry · acr · aks
                      (each with README + offline `terraform test`)
  stack/              composes the 7 modules; the only place they meet
  envs/dev|prod/      settings + state key only (no logic)
app/                  FastAPI service: workload identity, OpenAI v1 SDK, OpenTelemetry, 16 tests
k8s/                  Kustomize base + overlays: PSA restricted, default-deny NetworkPolicies
policy/               Checkov config + OPA rules (Terraform plan + Kubernetes) with tests
scripts/              deploy-app · smoke-test · ask · security-test · opa-eval · plan-fingerprint · github-settings
.github/workflows/    ci · plan · deploy-dev · deploy-prod · drift
docs/                 architecture (+ diagram) · security · observability · runbook · ADRs
```

## Documentation

| Document | For |
|---|---|
| [Architecture](docs/architecture.md) | How every part connects: diagrams, identities, network, data flow |
| [Security](docs/security.md) | Threat model (STRIDE), blast radius, supply chain, accepted risks |
| [Observability](docs/observability.md) | What flows into the workspace, ready-to-run KQL |
| [Runbook](docs/runbook.md) | Setup, deploy, verify, roll back, drift response, teardown, real errors and fixes |
| [Policy](policy/README.md) | Every Checkov/OPA rule and why it exists |
| [Decisions (ADRs)](docs/adr/README.md) | 10 architecture decision records |

## Status

Dev has been deployed and verified end to end, both from a workstation and fully by the pipeline. Prod is defined and plan-verified: every PR plans it and OPA checks it, but it isn't kept running, for cost reasons.

## License

[MIT](LICENSE) © 2026 kenwulff
