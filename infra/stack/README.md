# Stack: the landing-zone composition

`infra/stack` is **one reusable composition** of the seven modules. Every environment (`infra/envs/dev`, `infra/envs/prod`) calls it with different settings, so dev and prod can't drift apart structurally.

```
network ─┬──────────────▶ private_dns ─┬─▶ key_vault
         │                             ├─▶ ai_foundry
monitoring ─(workspace)─▶ everything   └─▶ acr
         └──────────────────────────────▶ aks ─▶ app identity, kubelet identity
```

## Permission lines drawn here

| From | Role | To | Why |
|---|---|---|---|
| App identity | Cognitive Services OpenAI User | AI Foundry | Call the model (inference only) |
| App identity | Key Vault Secrets User | Key Vault | Read secrets (read only) |
| App identity | Monitoring Metrics Publisher | App Insights | Send telemetry (local auth is off) |
| Kubelet identity | AcrPull | Container Registry | Pull images through the Private Endpoint |
| AKS control plane | Network Contributor | VNet | Join the node subnet, use the NAT Gateway (inside the `aks` module) |

Every assignment sets `principal_type = "ServicePrincipal"` and uses a role from the bootstrap's allow-list, so the CI deploy identity's **ABAC-constrained** RBAC Administrator role permits it. Any other role, or any human assignee, is rejected by Azure.

## Naming

| Resource | Pattern | dev example |
|---|---|---|
| Resource group (from bootstrap) | `rg-<project>-<env>` | `rg-aifz-dev` |
| Most resources | `<type>-<project>-<env>` | `vnet-aifz-dev`, `aks-aifz-dev` |
| Globally unique | `+ <4-char random suffix>` | `kv-aifz-dev-x7k2`, `ais-aifz-dev-x7k2`, `acraifzdevx7k2` |

The suffix is generated **once** per environment and stored in state, so names never change on later plans.

## Outputs

Everything the app deployment and CI need: `aks_name`, `app_namespace`, `app_service_account`, `app_identity_client_id`, `acr_name`, `acr_login_server`, `foundry_openai_endpoint`, `foundry_deployment_names`, `key_vault_uri`, `log_analytics_workspace_id`, `application_insights_connection_string` (sensitive), `egress_public_ip`, `resource_group_name`, `name_suffix`.
