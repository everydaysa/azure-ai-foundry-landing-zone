# ADR-0004: One Log Analytics workspace, Entra-only telemetry

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

Telemetry comes from four sources: AI Foundry (model requests, throttling, content-filter events), AKS (control plane + container logs), supporting PaaS (Key Vault, ACR) and the application (OpenTelemetry traces). Split workspaces make incident response slow, because you can't join a failing request to the Foundry call and the pod that made it.

## Decision

1. **One Log Analytics workspace per environment.** Every diagnostic setting targets it.
2. **Workspace-based Application Insights**, so OpenTelemetry data lands in the same workspace.
3. **`local_authentication_enabled = false`** on both. The app sends telemetry with its workload identity and the *Monitoring Metrics Publisher* role.
4. **Retention and cost:** dev 30 days with a 1 GB/day cap; prod 90 days, uncapped.

## Consequences

- ✅ A single KQL query can trace request → pod → Foundry call.
- ✅ A leaked connection string can't inject or spoof telemetry.
- ⚠️ Ingestion and query use the public Azure Monitor endpoints (Entra-authenticated). **Production extension:** Azure Monitor Private Link Scope (AMPLS) with Private Endpoints, and `internet_ingestion_enabled = false`.
- ⚠️ The dev cap can drop logs during a runaway incident. That's accepted for dev only.
