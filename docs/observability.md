# Observability

**One Log Analytics workspace per environment receives everything:** application traces, container logs, Kubernetes audit, model request logs, vault access and registry events. One query language (KQL) answers any question across all of them.

Think of it as a security control room: every camera in the building feeds the same wall of screens, so you can follow one person from the front door to the vault without switching rooms.

## 1. What flows in

```
 source                        how it gets there                          lands in (tables)
 ─────────────────────────────  ────────────────────────────────────────  ─────────────────────────────────────
 aifz-app (FastAPI)            OpenTelemetry distro → App Insights         AppRequests · AppTraces · AppExceptions
                               authenticated with the WORKLOAD IDENTITY    AppDependencies · AppMetrics
 containers / pods / nodes     Container Insights (DCR, managed identity,  ContainerLogV2 · KubePodInventory
                               4 selected streams, every 5 min)            KubeEvents · KubeNodeInventory
 AKS control plane             diagnostic setting (resource-specific)      AKSAuditAdmin (every API write)
                                                                           AKSControlPlane (guard, autoscaler)
 AI Foundry                    diagnostic setting (allLogs + metrics)      AzureDiagnostics · AzureMetrics
 Key Vault                     diagnostic setting (allLogs + metrics)      AzureDiagnostics · AzureMetrics
 Container Registry            diagnostic setting (allLogs + metrics)      ContainerRegistryLoginEvents
                                                                           ContainerRegistryRepositoryEvents
```

Code: `infra/modules/monitoring` (workspace + App Insights), plus a `diag-to-central-workspace` diagnostic setting in every other module and the DCR in `infra/modules/aks`. The app side is `app/src/app/telemetry.py`.

## 2. Design choices

| Choice | Why |
|---|---|
| **One workspace**, workspace-based App Insights | A single query correlates app, cluster, platform and model; one place for RBAC and retention |
| **Local auth disabled** on Log Analytics *and* App Insights | The connection string only says *where* to send data. Writing requires an Entra token plus the **Monitoring Metrics Publisher** role, so a leaked string can't inject or forge telemetry. Checkov has no check for this, so **OPA rule T2** enforces it |
| **Container Insights via DCR with managed identity auth** | No workspace key on the nodes |
| **Only the streams we query, every 5 minutes** | The default collects every stream every minute. On idle dev, Perf + ContainerInventory + InsightsMetrics were ~285 MB/day that no query used. Node/pod CPU and memory stay available as free platform metrics |
| `kube-audit-admin` (not full `kube-audit`) | Captures every write to the API server (who changed what) without the volume of every read |
| Probes excluded from traces | `/healthz` and `/readyz` fire every few seconds; tracing them would be noise and cost |
| Only the `app` logger is exported | Library debug chatter stays out of the workspace |
| Resource-context access | A team with access to a resource can read *that resource's* logs without being granted the whole workspace |
| Dev: 30 days, 2 GB/day cap · Prod: 90 days, no cap | Dev can't run up a bill; the cap is sized from measured volume (§3) so normal days never trip it; prod never drops security evidence |

## 3. Measured volume and the daily cap

The cap is a guardrail. When it trips, ingestion stops for the rest of the day, **security audit and app traces included**. So the design goal is that normal days never trip it. Measured on idle dev (2 nodes, hourly `Usage`, steady from the first hour):

| Table | MB/hour | Finding |
|---|---|---|
| AKSAuditAdmin | ~40 | **82% of rows are `update leases`**: controllers renewing leader-election heartbeats every few seconds. No security value |
| Perf | ~20 | Not used by any query → no longer collected |
| ContainerInventory | ~12 | Not used → no longer collected |
| InsightsMetrics | ~5 | Not used → no longer collected |
| KubePodInventory | ~3.5 | Used; now collected every 5 min instead of every 1 min |
| **Total billable** | **~84** | **~2 GB/day: the original 1 GB cap would have tripped about 12 hours into every day** |

| Configuration | MB/hour | Per day | Result |
|---|---|---|---|
| Default Container Insights | ~84 | ~2.0 GB | Over a 1 GB cap |
| **Trimmed streams, every 5 min (current)** | **~44** | **~1.05 GB** | **Dev cap raised to 2 GB/day: ~2× headroom, still stops a runaway bug** |
| + lease-heartbeat filter (extension) | ~11 | ~0.26 GB | The cap could go back to 1 GB |

A lesson from getting this wrong first: a "last 24 hours" total from an environment that is only 9 hours old reads as a low daily rate. **Measure per hour, from the first full hour, before sizing a cap.**

**Production extension: filter lease heartbeats at ingestion (about −33 MB/hour).** A workspace transformation on `AKSAuditAdmin` can drop only the lease renewals and keep every other write. It isn't automated here on purpose. The workspace must reference the transformation rule, and the rule must reference the workspace, which azurerm can't express in one apply (the provider's own acceptance test uses two passes). The options are an `azapi_update_resource` patch after both exist, or a documented two-pass deploy. For this project, the measured numbers and the exact rule are the deliverable:

```kusto
// Workspace transformation for AKSAuditAdmin (drops only lease renewals; every other write is kept)
source | where not(Verb == "update" and tostring(ObjectRef.resource) == "leases")
```

```kusto
// Re-measure: billable MB per hour and table (size caps from this, not from a 24 h total)
Usage | where TimeGenerated > ago(24h) and IsBillable
| summarize MB = round(sum(Quantity), 1) by bin(TimeGenerated, 1h), DataType
| order by TimeGenerated desc, MB desc
```

## 4. Ready-to-run KQL

Open the workspace **log-aifz-dev** → *Logs* in the Azure portal, or use the CLI (section 4).

### Application

```kusto
// /chat latency and error rate, 5-minute buckets
AppRequests
| where TimeGenerated > ago(24h) and Name has "/chat"
| summarize requests = count(), failed = countif(Success == false),
            p50_ms = percentile(DurationMs, 50), p95_ms = percentile(DurationMs, 95)
  by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

```kusto
// Token usage reported by the app (from the "chat ok" log line)
AppTraces
| where TimeGenerated > ago(24h) and Message startswith "chat ok"
| extend prompt = toint(extract(@"prompt_tokens=(\d+)", 1, Message)),
         completion = toint(extract(@"completion_tokens=(\d+)", 1, Message))
| summarize calls = count(), prompt_tokens = sum(prompt), completion_tokens = sum(completion)
```

```kusto
// Every error the app logged, newest first (identity, RBAC, network or model failures)
AppTraces
| where TimeGenerated > ago(7d) and SeverityLevel >= 3
| project TimeGenerated, AppRoleName, Message
| order by TimeGenerated desc
```

### Cluster

```kusto
// Container logs for the app, including anything printed before telemetry started
ContainerLogV2
| where TimeGenerated > ago(1h) and PodNamespace == "ai-app"
| project TimeGenerated, PodName, ContainerName, LogMessage
| order by TimeGenerated desc
```

```kusto
// Pod restarts and warning events (crash loops, image pull failures, policy rejections)
KubeEvents
| where TimeGenerated > ago(24h) and Namespace == "ai-app" and KubeEventType == "Warning"
| project TimeGenerated, Name, Reason, Message
| order by TimeGenerated desc
```

### Security and audit

```kusto
// WHO changed WHAT in Kubernetes: every write to the API server
AKSAuditAdmin
| where TimeGenerated > ago(7d)
| where Verb in ("create", "update", "patch", "delete")
| extend user = tostring(User.username), resource = tostring(ObjectRef.resource),
         ns = tostring(ObjectRef.namespace), name = tostring(ObjectRef.name)
| where user !startswith "system:"            // hide Kubernetes' own controllers
| project TimeGenerated, user, Verb, resource, ns, name
| order by TimeGenerated desc
```

```kusto
// Who accessed the model's control and data plane
AzureDiagnostics
| where TimeGenerated > ago(24h) and ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| summarize calls = count() by Category, OperationName, ResultSignature, CallerIPAddress
| order by calls desc
```

```kusto
// Key Vault access (expect only the app identity and the platform)
AzureDiagnostics
| where TimeGenerated > ago(7d) and ResourceProvider == "MICROSOFT.KEYVAULT"
| summarize count() by OperationName, ResultSignature, CallerIPAddress
```

```kusto
// Registry: every login and every push (pushes should come only from the deploy job)
union ContainerRegistryLoginEvents, ContainerRegistryRepositoryEvents
| where TimeGenerated > ago(7d)
| project TimeGenerated, Type, OperationName, Identity, CallerIpAddress, Repository, Tag
| order by TimeGenerated desc
```

### One incident timeline (correlate everything)

```kusto
// Everything that happened around a failure, from every source, on one timeline
let t0 = ago(2h); let t1 = now();
union
  (AppRequests    | where TimeGenerated between (t0 .. t1) and Success == false
                  | project TimeGenerated, source = "app-request", detail = strcat(Name, " → ", ResultCode)),
  (AppTraces      | where TimeGenerated between (t0 .. t1) and SeverityLevel >= 3
                  | project TimeGenerated, source = "app-log", detail = Message),
  (KubeEvents     | where TimeGenerated between (t0 .. t1) and Namespace == "ai-app"
                  | project TimeGenerated, source = "k8s-event", detail = strcat(Reason, ": ", Message)),
  (AKSAuditAdmin  | where TimeGenerated between (t0 .. t1) and tostring(ObjectRef.namespace) == "ai-app"
                  | project TimeGenerated, source = "k8s-audit",
                            detail = strcat(tostring(User.username), " ", Verb, " ", tostring(ObjectRef.resource), "/", tostring(ObjectRef.name))),
  (AzureDiagnostics | where TimeGenerated between (t0 .. t1) and ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
                    | project TimeGenerated, source = "foundry", detail = strcat(OperationName, " ", ResultSignature))
| order by TimeGenerated asc
```

## 5. From the command line

```bash
WS=$(az monitor log-analytics workspace show -g rg-aifz-dev -n log-aifz-dev --query customerId -o tsv)
az monitor log-analytics query -w "$WS" -o table --analytics-query '
  AppRequests | where TimeGenerated > ago(1h) | summarize count() by Name, ResultCode'
```

Reading logs needs **Log Analytics Reader** (or higher) on the workspace or on the resource whose logs you want (resource-context access).

## 6. Signals worth alerting on (production extension)

| Alert | Query basis | Why |
|---|---|---|
| `/chat` 5xx rate > 5% for 10 min | `AppRequests` | Identity, network or model failure |
| Any `model call denied` log | `AppTraces` | RBAC or private-network path broken |
| Kubernetes write by a non-pipeline human identity in prod | `AKSAuditAdmin` | Change outside the pipeline |
| Registry push not from the deploy identity | `ContainerRegistryRepositoryEvents` | Possible image tampering |
| Drift issue opened | GitHub issue (`drift.yml`) | Azure changed outside Terraform |
| Log ingestion hits the daily cap (dev) | `_LogOperation` | Data is being dropped |
