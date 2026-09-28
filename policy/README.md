# Policy as code

Two engines, three layers, one rule: **if a control matters, a machine checks it on every change.**

```
            ┌───────────── what is checked ─────────────┐
 change ──▶ │ 1. Checkov   the CODE     .tf · k8s · Dockerfile · workflows  (1,000+ built-in checks)
            │ 2. OPA       the PLAN     terraform show -json tfplan  (OUR rules, resolved values)
            │ 3. OPA       the RENDER   kubectl kustomize output     (OUR rules, final manifests)
            └───────────────────────────────────────────┘
                  │ any failure ⇒ exit 1 ⇒ PR blocked / deploy stops
                  ▼
 in Azure:  Azure Policy (Gatekeeper) on AKS + Pod Security Admission "restricted"
```

**Why both?** Checkov knows hundreds of generic best practices but can't know *our* architecture. OPA encodes the decisions in our ADRs, e.g. "prod AKS must be Standard tier" and "telemetry must be Entra-only". It evaluates the **plan**, where variables, defaults and module wiring are already resolved.

## Layout

```
policy/
├── checkov/.checkov.yaml          one config for local runs and CI
└── opa/
    ├── terraform/                 package terraform   (input: plan JSON)
    │   ├── lib.rego               resources-after-apply, tag helpers
    │   ├── identity.rego          zero keys: Foundry, Log Analytics, App Insights, ACR
    │   ├── network.rego           no public access: Foundry, Key Vault; Foundry egress restricted
    │   ├── aks.rego               private, no local accounts, workload identity, policy add-on; PROD = Standard tier
    │   ├── rbac.rego              never Owner / User Access Administrator / RBAC Administrator
    │   ├── tags.rego              project · environment · managed_by on every taggable resource
    │   └── terraform_test.rego    24 unit tests
    └── kubernetes/                package kubernetes  (input: rendered manifests)
        ├── workload.rego          digest-pinned images · non-root · read-only FS · no escalation
        │                          · drop ALL · no host namespaces · PSA restricted · no LB/NodePort
        └── workload_test.rego     19 unit tests
```

## The rules

| # | Rule | Engine | Why (ADR) |
|---|---|---|---|
| T1 | Foundry `local_auth_enabled = false` | OPA plan + Checkov | Keys can't authenticate (0001, 0005) |
| T2 | Log Analytics + App Insights `local_authentication_enabled = false` | **OPA only** (no Checkov check exists) | Entra-only telemetry (0004) |
| T3 | ACR admin user off, anonymous pull off | OPA plan + Checkov | Identity-only registry (0006) |
| T4 | Foundry + Key Vault `public_network_access_enabled = false` | OPA plan + Checkov | Private Endpoints only |
| T5 | Foundry `outbound_network_access_restricted = true` | OPA plan | Exfiltration guard (0005) |
| T6 | AKS private, no public FQDN, local accounts off, OIDC + workload identity, Azure Policy | OPA plan + Checkov | (0007) |
| T7 | **prod** AKS `sku_tier = "Standard"` | **OPA only** | Replaces the skipped CKV_AZURE_170 (0007) |
| T8 | No Owner / UAA / RBAC Admin role assignment (by name **or** ID) | **OPA only** | Pipelines can't escalate (0002) |
| T9 | Required tags; `environment` ∈ {dev, prod} | **OPA only** | Ownership + drives T7 |
| K1 | Images pinned by `@sha256:` digest (containers + initContainers) | OPA render + Checkov | Supply chain (0008) |
| K2 | `runAsNonRoot`, never UID 0 | OPA render + PSA | (0008) |
| K3 | `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, drop ALL, not privileged | OPA render + PSA | (0008) |
| K4 | No hostNetwork / hostPID / hostIPC | OPA render + PSA | Node isolation |
| K5 | Namespaces enforce PSA `restricted` | OPA render | Cluster keeps enforcing if manifests drift |
| K6 | No `LoadBalancer` / `NodePort` Services | OPA render | No public entry points |

T9 guards T7: removing the `environment` tag to dodge the prod rule fails the tag rule instead.

## Run it

```bash
make checkov                 # Checkov: Terraform + Kubernetes + Dockerfile + workflows
make opa-test                # prove every rule: compliant input passes, violation is denied
make policy-k8s ENV=dev      # OPA on the rendered manifests (base if no generated values)
make plan ENV=dev && make policy-plan ENV=dev    # OPA on the real plan (needs az login)
make policy                  # checkov + opa-test + policy-k8s (offline; what CI runs on every PR)
```

## Skips are explicit and reviewed

Checkov skips live **next to the code** as `#checkov:skip=<ID>: <reason>` and every one is tied to an ADR (search: `grep -rn "checkov:skip" infra app`). A skip is a documented decision, never a silenced alarm. Where a Checkov skip weakens a control for dev only (CKV_AZURE_170), an OPA rule restores it for prod.
