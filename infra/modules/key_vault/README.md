# Module: `key_vault`

A private, RBAC-only, audited vault for the few things Azure identity can't replace, such as third-party API keys or TLS certificates.

```
AKS pod (workload identity, Key Vault Secrets User)
  └─ tcp/443 ─▶ pe-kv-<prefix>-<suffix> (10.x.4.y) ─▶ kv-<prefix>-<suffix>
                      ▲                                public access: DISABLED
 privatelink.vaultcore.azure.net (A record from the DNS zone group)
                                  allLogs (AuditEvent) + AllMetrics ─▶ central workspace
```

## Security properties

| Property | Setting |
|---|---|
| One permission model | `rbac_authorization_enabled = true` (no access policies) |
| No public endpoint | `public_network_access_enabled = false` + `network_acls { default_action = "Deny", bypass = "None" }` |
| Private access | Private Endpoint (`vault` sub-resource) in the PE subnet; DNS record written automatically |
| Recoverable | `purge_protection_enabled = true`; `soft_delete_retention_days` = 7 in dev, 90 in prod |
| No side doors | `enabled_for_deployment / disk_encryption / template_deployment = false` |
| Every access audited | Diagnostic setting `allLogs` → central Log Analytics workspace |
| Least privilege for workloads | `Key Vault Secrets User` (read-only) per workload identity |
| **Separation of duties** | The deploy pipeline has Contributor (control plane) only, and no data-plane role, so it can build the vault but **cannot read its secrets** |

Checkov: 6/6 passed (CKV_AZURE_42, 109, 110, 111, 189, CKV2_AZURE_32).

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix` / `name_suffix` | Vault name = `kv-<prefix>-<suffix>` (≤ 24 chars) | — |
| `location`, `resource_group_name`, `tenant_id` | Placement | — |
| `sku_name` | `standard` / `premium` | `standard` |
| `soft_delete_retention_days` | 7–90 | `90` |
| `private_endpoint_subnet_id` | From `network` | — |
| `private_dns_zone_id` | `vaultcore` zone from `private_dns` | — |
| `log_analytics_workspace_id` | From `monitoring` | — |
| `secrets_user_principal_ids` | `{ name = principal_id }` → Key Vault Secrets User | `{}` |
| `tags` | Tags | `{}` |

## Outputs

`id`, `name`, `vault_uri`, `private_endpoint_ip`

## Tests

```bash
terraform init -backend=false && terraform test
```

These check the lockdown settings, the PE ↔ DNS ↔ subnet wiring, audit logs going to the central workspace, read-only workload access, and retention validation.

## Operational note: teardown

With purge protection on, a destroyed vault stays **soft-deleted** for the retention period. That costs nothing, but its name stays reserved. The random `name_suffix` means a redeploy never collides. To see soft-deleted vaults: `az keyvault list-deleted -o table`.
