# Azure AI Foundry Secure Landing Zone

> A production-grade, security-first foundation for running AI workloads on Azure.
> **Zero model API keys. Zero public PaaS endpoints. One place for all telemetry.**

**Status:** 🚧 under construction. Full documentation lands in Step 15.

## At a glance

| Principle | How it is enforced |
|---|---|
| No model API keys | Foundry `local_auth_enabled = false`; the AKS app authenticates with **Workload Identity** (OIDC federation) |
| No public PaaS endpoints | Foundry, Key Vault and ACR reachable only via **Private Endpoints + Private DNS** |
| No stored CI credentials | GitHub Actions log in to Azure with **OIDC federated credentials** |
| Centralised telemetry | One **Log Analytics workspace** for platform, cluster, and app (OpenTelemetry) signals |
| Guardrails in the pipeline | **Checkov + OPA** gate every pull request |

## Repository layout

```
infra/
  bootstrap/      One-time: remote state storage + GitHub OIDC identities
  modules/        7 reusable modules: network, monitoring, private_dns,
                  key_vault, ai_foundry, acr, aks
  stack/          Composes the modules into one landing zone
  envs/dev|prod/  Per-environment settings and state backends
app/              FastAPI service (Workload Identity + OpenTelemetry)
k8s/              Kustomize base + dev/prod overlays
policy/           Checkov config + OPA/Rego policies with tests
.github/workflows/ CI/CD pipelines
docs/             Architecture, security, observability, deploy, runbook, ADRs
```

## Quick start

```bash
make help        # list every command
make ci          # run all local checks (fmt, validate, lint, policy, tests)
```

## License

[MIT](LICENSE) © 2026 kenwulff
