# ADR-0003: Network egress through a NAT Gateway

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

New Azure subnets are private by default: there's no implicit outbound internet access. AKS nodes still need egress to pull system images, reach Entra ID and call Azure management APIs. Model traffic stays private through Private Endpoints.

Options considered:

| Option | Control | Cost (approx.) |
|---|---|---|
| AKS load-balancer outbound | Low: egress IP managed by AKS | Included |
| **NAT Gateway** | Medium: one static, known IP; no inbound possible | ≈ $1.10/day + data |
| Azure Firewall | High: FQDN allow-listing, TLS inspection, logging | ≈ $30+/day |

## Decision

Use a **NAT Gateway** with one static public IP. Attach it **only** to the AKS node subnet, and set AKS `outbound_type = "userAssignedNATGateway"`. Set `default_outbound_access_enabled = false` on every subnet, so no other path exists.

## Consequences

- ✅ All cluster egress leaves from a single, documented IP, so partners can allow-list it.
- ✅ The NAT Gateway is outbound-only; it cannot be used for inbound connections.
- ⚠️ Egress isn't filtered by destination. Production should put **Azure Firewall** (or an NVA) in a hub, with a UDR `0.0.0.0/0 → firewall` and an FQDN allow-list based on the AKS outbound requirements.
