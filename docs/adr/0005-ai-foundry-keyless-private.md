# ADR-0005: AI Foundry is keyless, private, and pinned

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

Model API keys are the most common way AI platforms leak. They get pasted into app settings, notebooks and CI variables, they're shared across teams, and they're rarely rotated. A public endpoint plus a key means anyone who obtains the key can spend your quota and read model output.

## Decision

| Control | Implementation |
|---|---|
| No keys | `local_auth_enabled = false`. The app authenticates with its AKS workload identity. |
| No public path | Public network access disabled; one Private Endpoint registered in all three Foundry DNS zones |
| Least privilege | *Cognitive Services OpenAI User* for workloads (inference only) |
| Exfiltration guard | `outbound_network_access_restricted = true`, empty FQDN list |
| Predictable behavior | Pinned model version, `OnceCurrentVersionExpired` |
| Safety | `Microsoft.DefaultV2` content filter on every deployment |
| Data residency | `DataZoneStandard` preferred (processing stays in the US data zone) |
| Evidence | All logs and metrics → central workspace |

## Accepted trade-offs

| Checkov | Trade-off | Production extension |
|---|---|---|
| CKV2_AZURE_22 | Microsoft-managed encryption keys | Customer-managed key in Key Vault Premium / Managed HSM, with rotation policy and key-access auditing |

## Consequences

- ✅ There is no credential to steal: a leaked key string is useless.
- ✅ Every inference call is attributable to a named workload identity.
- ⚠️ Local tools (for example the Foundry portal's playground) also need network access to the Private Endpoint and an Entra login. Operators use a jump host, VPN, or temporarily add their IP to the account's `ip_rules`.
- ⚠️ Model choice depends on regional availability and subscription quota. Check both before `apply` (see the module README).
