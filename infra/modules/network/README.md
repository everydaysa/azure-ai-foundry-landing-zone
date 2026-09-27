# Module: `network`

The private network every other module plugs into.

```
vnet-<prefix>  10.x.0.0/16
├── snet-aks-nodes          10.x.0.0/22   NSG: no Internet inbound
│        └── NAT Gateway ──▶ pip-<prefix>-nat (one static egress IP)
├── snet-private-endpoints  10.x.4.0/24   NSG: ONLY tcp/443 from snet-aks-nodes, no outbound
└── 10.x.5.0 – 10.x.255.255               reserved (API-server subnet, runners, …)
```

## Security properties

| Property | How |
|---|---|
| No implicit internet egress | `default_outbound_access_enabled = false` on every subnet |
| One known egress path | NAT Gateway with a static IP, attached **only** to the AKS subnet |
| No inbound from the internet | Explicit `deny-internet-inbound` NSG rule; nothing in the platform has a public ingress |
| Micro-segmented PaaS access | PE subnet NSG allows **only** tcp/443 from the AKS node subnet, denies all other VNet traffic, and denies all outbound |
| NSGs actually enforced on PEs | `private_endpoint_network_policies = "Enabled"` (without it, PE NSGs are silently ignored) |
| Identical layout per environment | Subnets are derived with `cidrsubnet()` from one `/16` input |

## Why CNI Overlay makes this simple

With Azure CNI **Overlay** (configured in the `aks` module), pods get IPs from a private overlay range that is **not** part of the VNet. When a pod calls a Private Endpoint, the traffic is SNAT-ed to the node IP. So "allow from `snet-aks-nodes`" is exactly "allow from the cluster", and a `/22` is plenty.

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix` | e.g. `aifz-dev` | — |
| `location` | Azure region | — |
| `resource_group_name` | Existing RG (from bootstrap) | — |
| `address_space` | VNet `/16` | — |
| `private_endpoint_allowed_sources` | Extra CIDRs allowed to reach PEs on 443 | `[]` |
| `nat_idle_timeout_minutes` | NAT TCP idle timeout | `10` |
| `tags` | Tags | `{}` |

## Outputs

`vnet_id`, `vnet_name`, `aks_nodes_subnet_id`, `private_endpoints_subnet_id`, `subnet_prefixes`, `nat_gateway_id`, `egress_public_ip`

## Tests

```bash
terraform init -backend=false && terraform test
```

These are offline unit tests with a mocked provider. They assert the subnet layout, that there's no default outbound access, PE network policies, and the 443-only rule, and they check that a non-`/16` address space is rejected.

## Production extensions (not built, deliberately)

- **Azure Firewall / NVA** instead of the NAT Gateway, for FQDN-based egress allow-listing (≈ $30+/day). See ADR-0003.
- **VNet flow logs** + Traffic Analytics into the central Log Analytics workspace.
- **Hub-and-spoke** peering to a connectivity hub with a DNS Private Resolver and a VPN/ExpressRoute gateway.
