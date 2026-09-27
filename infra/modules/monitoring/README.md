# Module: `monitoring`

The single control room for every signal in the landing zone.

```
AI Foundry · AKS · Key Vault · ACR ──(diagnostic settings, added by each module)──┐
                                                                                   ▼
                                                     log-<prefix>  Log Analytics workspace
                                                                                   ▲
FastAPI app ──(OpenTelemetry + Entra token)──▶ appi-<prefix> (workspace-based) ────┘
```

## Security and operations properties

| Property | How |
|---|---|
| **One** workspace for platform + cluster + app | App Insights is *workspace-based* (`workspace_id`), so its tables (`AppRequests`, `AppDependencies`, …) live next to `AzureDiagnostics`, `ContainerLogV2`, etc. One KQL query can join them. |
| No key-based ingestion or query | `local_authentication_enabled = false` on **both** resources. The connection string only says *where* to send data; the app must also present an Entra token and hold **Monitoring Metrics Publisher**. |
| Least-privilege log reading | `allow_resource_only_permissions = true` (resource-context RBAC) |
| Cost guardrail in dev | `daily_quota_gb` caps ingestion (dev: 1 GB/day); prod is uncapped so security logs are never dropped |
| Retention per environment | dev 30 days, prod 90 days (`retention_in_days`) |

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix` | e.g. `aifz-dev` | — |
| `location` | Azure region | — |
| `resource_group_name` | Existing RG (from bootstrap) | — |
| `retention_in_days` | 30–730 | `30` |
| `daily_quota_gb` | `-1` = unlimited | `-1` |
| `tags` | Tags | `{}` |

## Outputs

`log_analytics_workspace_id`, `log_analytics_workspace_name`, `log_analytics_customer_id`, `application_insights_id`, `application_insights_connection_string` (sensitive)

## Tests

```bash
terraform init -backend=false && terraform test
```

These check that auth is Entra-only on both resources, that App Insights is linked to the workspace, the dev cap and prod profile, and that retention below 30 days is rejected.

## Policy note

Checkov 3.3 has **no built-in checks** for `azurerm_log_analytics_workspace` or `azurerm_application_insights`. The "local auth disabled" rule is therefore enforced by our own **OPA policy** (Step 13). That's a concrete example of why the pipeline runs both tools.

## Production extensions

- **Azure Monitor Private Link Scope (AMPLS)**, so ingestion and query go through Private Endpoints (ADR-0004).
- Data Collection Rule-based transformations to drop or mask noisy or sensitive fields before ingestion.
- Workspace-level alert rules and action groups (for example Foundry 429 throttling, or pod restarts).
