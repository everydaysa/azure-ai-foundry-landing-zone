# Module: `private_dns`

The internal phone book that makes Private Endpoints work.

```
app asks: myfoundry.cognitiveservices.azure.com
  └─ public DNS: CNAME → myfoundry.privatelink.cognitiveservices.azure.com
       └─ privatelink zone LINKED to our VNet → A 10.x.4.y (Private Endpoint)  ✅
          (from the internet: no link → public IP → blocked)                    ❌
```

| Logical key | Zone | Used by |
|---|---|---|
| `cognitiveservices` | `privatelink.cognitiveservices.azure.com` | AI Foundry |
| `openai` | `privatelink.openai.azure.com` | AI Foundry (OpenAI-compatible API) |
| `aiservices` | `privatelink.services.ai.azure.com` | AI Foundry (AI Services / Foundry projects) |
| `keyvault` | `privatelink.vaultcore.azure.net` | Key Vault |
| `acr` | `privatelink.azurecr.io` | Container Registry (login + data endpoints) |
| *(optional)* `aks` | `privatelink.<region>.azmk8s.io` | Private AKS API server, via `extra_zones` |

## Design decisions

| Decision | Why |
|---|---|
| **Three zones for AI Foundry** | One Foundry (AIServices) account answers on three hostnames. Missing one means that API resolves publicly and fails, a classic outage. |
| **Zones created here, A records written by each Private Endpoint** | Private Endpoints use `private_dns_zone_group`, so IPs are never hard-coded and records are removed with the endpoint. |
| `registration_enabled = false` | privatelink zones hold PE records only; VM hostnames never belong here. |
| `resolution_policy = "Default"` (strict) | A missing record fails loudly (NXDOMAIN) instead of silently falling back to the public IP. |
| Zones are a **map input** | Adding a service (AI Search, Storage) or the AKS zone is one line, with no module change. |
| Validation: only `privatelink.*` names | Stops this module from being misused for general DNS. |

## Enterprise note

In a hub-and-spoke Azure Landing Zone, these zones exist **once**, in the connectivity subscription. They're linked to every spoke VNet and to a **DNS Private Resolver** for on-premises clients, and Azure Policy (DeployIfNotExists) writes the records automatically. In this project each environment owns its own zones, which keeps it self-contained. The module interface (`zone_ids` output) stays the same either way, so moving to a central hub only changes where the IDs come from.

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix` | Used in link names | — |
| `resource_group_name` | RG that owns the zones | — |
| `virtual_network_id` | VNet to link (validated ARM ID) | — |
| `zones` | Logical key → zone name | the 5 zones above |
| `extra_zones` | Merged into `zones` | `{}` |
| `tags` | Tags | `{}` |

## Outputs

`zone_ids`, `zone_names`, `vnet_link_ids` (all keyed by logical name)

## Tests

```bash
terraform init -backend=false && terraform test
```

These check that all 5 default zones exist, each is linked with registration off, `extra_zones` merge correctly, and that non-privatelink zones and malformed VNet IDs are rejected.
