# Architecture Decision Records

Each ADR records one decision: the context, what was decided, the alternatives rejected, and the consequences, including the trade-offs we accepted.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-keyless-identity.md) | Keyless identity everywhere (OIDC federation + managed identities) | Accepted |
| [0002](0002-terraform-state-and-bootstrap.md) | Terraform state and bootstrap trade-offs | Accepted |
| [0003](0003-network-egress.md) | Network egress through a NAT Gateway | Accepted |
| [0004](0004-centralized-observability.md) | One Log Analytics workspace, Entra-only telemetry | Accepted |
| [0005](0005-ai-foundry-keyless-private.md) | AI Foundry is keyless, private, and pinned | Accepted |
| [0006](0006-registry-just-in-time-ci-access.md) | Container registry with just-in-time CI access | Accepted |
| [0007](0007-private-aks-workload-identity.md) | Private AKS with workload identity | Accepted |
| [0008](0008-kubernetes-workload-hardening.md) | Kubernetes workload hardening and network policy | Accepted |
| [0009](0009-policy-as-code.md) | Policy as code with Checkov + OPA | Accepted |
| [0010](0010-cicd-pipeline.md) | CI/CD with GitHub Actions: keyless, least-privilege, gated | Accepted |

New decision? Copy the structure of any ADR (Context → Decision → Alternatives → Consequences), number it next, and link it here in the same PR.
