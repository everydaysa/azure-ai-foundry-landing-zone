# ADR-0004: One Log Analytics workspace, Entra-only telemetry

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

Telemetry comes from four sources: AI Foundry (model requests, throttling, content-filter events), AKS (control plane + container logs), supporting PaaS (Key Vault, ACR) and the application (OpenTelemetry traces). Split workspaces make incident response slow, because you can't join a failing request to the Foundry call and the pod that made it.

## Decision

1. **One Log Analytics workspace per environment.** Every diagnostic setting targets it.
2. **Workspace-based Application Insights**, so OpenTelemetry data lands in the same workspace.
3. **`local_authentication_enabled = false`** on both. The app sends telemetry with its workload identity and the *Monitoring Metrics Publisher* role.
4. **Retention and cost:** dev 30 days with a 2 GB/day cap (sized from measured volume); prod 90 days, uncapped.

## Consequences

- ✅ A single KQL query can trace request → pod → Foundry call.
- ✅ A leaked connection string can't inject or spoof telemetry.
- ⚠️ Ingestion and query use the public Azure Monitor endpoints (Entra-authenticated). **Production extension:** Azure Monitor Private Link Scope (AMPLS) with Private Endpoints, and `internet_ingestion_enabled = false`.
- ⚠️ The dev cap can drop logs during a runaway incident. That's accepted for dev only.
- ⚠️ **Measured, not assumed:** idle dev ingested ~84 MB/hour (~2 GB/day, twice the original 1 GB cap, which would have tripped every day and dropped the audit trail). 82% of the Kubernetes audit rows were lease heartbeats, and Container Insights' default stream group sent ~37 MB/hour nobody queried. Container Insights now collects 4 streams every 5 minutes (~44 MB/hour), and the dev cap is 2 GB/day. The lease filter (~11 MB/hour total) is documented as a production extension in [observability.md](../observability.md#3-measured-volume-and-the-daily-cap).
