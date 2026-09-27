# Module: `acr`

A Premium container registry that nobody can reach from the internet at rest. AKS pulls images privately, and CI pushes through a **just-in-time** firewall opening.

```
GitHub Actions ──(JIT: add own IP → push with Entra token → remove IP in always())──┐
                                                                                    ▼
                       acr<prefix><suffix>   Premium · zone-redundant · firewall DENY · 0 IP rules at rest
AKS kubelet ──AcrPull──▶ pe-acr… (10.x.4.y) ─┘   admin OFF · anonymous pull OFF · dedicated data endpoints
   privatelink.azurecr.io: login server + <name>.<region>.data.azurecr.io
                       ContainerRegistryLoginEvents + RepositoryEvents ─▶ central workspace
```

## Security properties

| Property | Setting |
|---|---|
| Identity-only access | `admin_enabled = false`, `anonymous_pull_enabled = false`; push and pull use Entra tokens + RBAC (AcrPush / AcrPull) |
| Private pulls | Private Endpoint (`registry` sub-resource). The DNS zone group registers the login server **and** the regional data endpoint |
| Closed at rest | `network_rule_set.default_action = "Deny"`, **no IP rules**, `network_rule_bypass_option = "None"` |
| Just-in-time CI access | The workflow adds its runner IP, pushes, then removes the rule in `always()`. Terraform's desired state is "no IP rules", so a leftover rule is **removed on the next apply** (self-healing) |
| Scoped data plane | `data_endpoint_enabled = true`: layers are served from a per-registry, per-region hostname |
| Hygiene | Untagged manifests purged after `untagged_retention_days` (default 7) |
| Resilience | `zone_redundancy_enabled = true` by default (no extra cost on Premium in eastus2) |
| Audit | Login + repository events → central workspace |

Checkov: 6 passed, 4 skipped with justification (see ADR-0006):

| Skipped | Reason |
|---|---|
| CKV_AZURE_139 public network | Deny-by-default with zero standing rules; JIT only |
| CKV_AZURE_166 quarantine | Images are scanned in CI (Trivy) before push; Defender for Containers scans at rest |
| CKV_AZURE_165 geo-replication | Single-region landing zone |
| CKV_AZURE_164 content trust | Docker Content Trust is retired; integrity comes from digest pinning + SBOM |

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix` / `name_suffix` | Registry name = `acr<prefix without hyphens><suffix>` | — |
| `location`, `resource_group_name` | Placement | — |
| `private_endpoint_subnet_id` | From `network` | — |
| `private_dns_zone_id` | `acr` zone from `private_dns` | — |
| `log_analytics_workspace_id` | From `monitoring` | — |
| `zone_redundancy_enabled` | Availability-zone redundancy | `true` |
| `untagged_retention_days` | Purge untagged manifests after N days | `7` |
| `acr_pull_principal_ids` | `{ name = principal_id }` → AcrPull | `{}` |
| `tags` | Tags | `{}` |

## Outputs

`id`, `name`, `login_server`

## Tests

```bash
terraform init -backend=false && terraform test
```

These check the alphanumeric name, identity-only access, the deny-by-default firewall with no standing rules, PE + DNS wiring, central logging, and pull-only consumers.
