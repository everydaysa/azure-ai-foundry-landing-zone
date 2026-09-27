# ADR-0002: Terraform state and bootstrap trade-offs

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

Remote state holds resource IDs and can hold sensitive values. It needs strong access control, recovery and locking. The pipelines run on **GitHub-hosted runners**, which live on the public internet and do not have fixed IP addresses.

## Decision

- A dedicated storage account (ZRS) with **shared keys disabled**, TLS 1.2, infrastructure encryption, blob **versioning**, **change feed** and **30-day soft delete** for blobs and containers, plus a **CanNotDelete** lock.
- One container, one state file per environment (`dev.tfstate`, `prod.tfstate`), locked through blob leases.
- The bootstrap uses local state (the chicken-and-egg problem). It is optional to migrate it into the account afterwards.

## Accepted trade-offs (Checkov skips with justification)

| Check | Trade-off | Enterprise extension |
|---|---|---|
| CKV_AZURE_59 / CKV_AZURE_35 / CKV2_AZURE_33 | Public endpoint enabled (Entra-only) so GitHub-hosted runners can reach state | Self-hosted runners in the VNet + a Private Endpoint on state + `public_network_access = "Disabled"` |
| CKV2_AZURE_1 | Microsoft-managed keys (+ infrastructure double encryption) | Customer-managed key in a dedicated Key Vault / Managed HSM |
| CKV2_AZURE_21 | Blob diagnostic logs not routed; change feed + versioning are the audit trail | Diagnostic setting to the central Log Analytics workspace |
| CKV_AZURE_206 | ZRS rather than geo-redundant | GZRS for regulated workloads |
| CKV_AZURE_33 | Queue logging not applicable (queues unused) | — |

## Consequences

- ✅ No storage keys exist to leak. State access requires an Entra token and is scoped per identity.
- ✅ Accidental deletion or corruption is recoverable (lock, versions, soft delete).
- ⚠️ The state endpoint is internet-reachable (authenticated only). This is the main thing to change for a regulated production rollout.
