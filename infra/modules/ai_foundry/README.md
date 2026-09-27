# Module: `ai_foundry`

The centerpiece: an Azure AI Foundry (AIServices) account with **no API keys**, **no public endpoint**, a Foundry project, and pinned model deployments.

```
AKS pod ──(Entra token + "Cognitive Services OpenAI User")──443──┐
                                                                 ▼
         pe-ais-<prefix>-<suffix> (10.x.4.y) ──▶ ais-<prefix>-<suffix>   kind = AIServices
A records in 3 zones:                              ├─ local_auth_enabled = false   ← NO API keys
  privatelink.cognitiveservices.azure.com          ├─ public network access OFF
  privatelink.openai.azure.com                     ├─ outbound access restricted
  privatelink.services.ai.azure.com                ├─ Foundry project (own managed identity)
                                                   └─ model deployment(s), pinned + content-filtered
                      allLogs + AllMetrics ─▶ central Log Analytics workspace
```

## Security properties

| Property | Setting |
|---|---|
| **Zero model API keys** | `local_auth_enabled = false`: keys can't authenticate even if listed. Every call needs an Entra token. |
| **No public endpoint** | `public_network_access_enabled = false`, `network_acls.default_action = "Deny"`, `bypass = "None"` |
| **One PE, three hostnames** | The Private Endpoint (`account` sub-resource) registers in the Cognitive Services, OpenAI and AI Services zones |
| **Exfiltration guard** | `outbound_network_access_restricted = true` with an empty FQDN allow-list |
| **Least-privilege callers** | Workloads get *Cognitive Services OpenAI User*: inference only; can't list keys, change deployments, or manage the account |
| **Pinned models** | `version_upgrade_option = "OnceCurrentVersionExpired"`: no silent behavior change; moves only when the pinned version retires |
| **Content safety** | `rai_policy_name = "Microsoft.DefaultV2"`: harm categories + prompt-injection / jailbreak shields |
| **Data residency option** | `DataZoneStandard` keeps processing inside the US data zone |
| **Full audit trail** | `allLogs` (Audit, RequestResponse, Trace) + `AllMetrics` → central workspace |
| **Managed identity** | System-assigned identity on the account and on the project |

Checkov: 4 passed, 1 skipped with justification (CKV2_AZURE_22, customer-managed keys; see ADR-0005).

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix` / `name_suffix` | Account name and subdomain = `ais-<prefix>-<suffix>` | — |
| `location`, `resource_group_name` | Placement | — |
| `private_endpoint_subnet_id` | From `network` | — |
| `private_dns_zone_ids` | Map with **cognitiveservices, openai, aiservices** (validated) | — |
| `log_analytics_workspace_id` | From `monitoring` | — |
| `project_name` | Foundry project name | `platform` |
| `model_deployments` | `{ <deployment> = { model_name, model_version, sku_name, capacity } }` | — |
| `openai_user_principal_ids` | `{ name = principal_id }` → Cognitive Services OpenAI User | `{}` |
| `tags` | Tags | `{}` |

## Outputs

`id`, `name`, `endpoint`, `openai_endpoint`, `project_id`, `deployment_names`, `account_principal_id`

## Tests

```bash
terraform init -backend=false && terraform test
```

These check: no keys and no public access; the PE registers in exactly the three Foundry zones; deployments are pinned and content-filtered with the requested SKU and capacity; inference-only role; logs to the central workspace; a missing Foundry zone is rejected; provisioned (committed-spend) SKUs are rejected.

## Choosing a model before `apply`

Model availability and quota vary by region **and** subscription. Check both before setting `model_deployments`:

```bash
az cognitiveservices model list --location eastus2 \
  --query "[?model.name=='gpt-4.1-mini'].{v:model.version, status:model.lifecycleStatus, retires:model.deprecation.inference}" -o table
az cognitiveservices usage list --location eastus2 \
  --query "[?contains(name.value,'gpt-4.1-mini')].{quota:name.value, used:currentValue, limit:limit}" -o table
```

## Teardown note

A deleted AIServices account is soft-deleted for 48 hours. The azurerm provider purges it on destroy by default (`features.cognitive_account.purge_soft_delete_on_destroy`), and the random suffix prevents name collisions either way.
