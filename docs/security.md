# Security

This document explains what we protect, from whom, and how each threat is stopped, with every control traced to the code that implements it and the check that proves it.

## 1. What we protect

| Asset | Why it matters |
|---|---|
| **Model access** (Foundry deployment) | Costs money per token; prompts and completions may contain sensitive data |
| **The Azure environment** (dev/prod resource groups) | Whoever controls it controls everything above |
| **Terraform state** | Contains every resource ID and configuration: a map of the estate |
| **Container images** | Whatever runs in the cluster runs with the app's identity |
| **Telemetry** | Evidence for incident response; must be complete and unforgeable |

## 2. Security principles

1. **No secrets exist.** No API keys, client secrets, passwords or storage keys. Every principal authenticates with a short-lived token (ADR-0001).
2. **No public PaaS endpoints.** Foundry and Key Vault have public access disabled and are reachable only via Private Endpoints. ACR is deny-by-default (ADR-0005, 0006).
3. **Least privilege, split by stage.** Read-only for plans, one resource group per deploy identity, inference-only for the app (ADR-0010).
4. **Every control is checked twice.** Once before the change (Checkov/OPA), once at runtime (Azure/Kubernetes enforcement), and again nightly (ADR-0009).
5. **Assume breach, limit the blast radius.** A compromised pod or pipeline run gets as little as possible.

## 3. Threat model (STRIDE)

| # | Threat | Example | Controls | Where enforced | Proven by |
|---|---|---|---|---|---|
| S1 | **Spoofing**: stolen model API key | Key leaked in code, logs or a laptop | Keys disabled on Foundry (`local_auth_enabled = false`) | Foundry rejects key auth | OPA T1 · Checkov · module test · Owner got `PermissionDenied` without a data-plane role |
| S2 | Spoofing: stolen CI credential | Secret exfiltrated from GitHub | **No CI secret exists.** OIDC federation, subject pinned to repo **ID** + context | Entra ID exact subject match | AADSTS700213 when the subject didn't match (the incident in the runbook) |
| S3 | Spoofing: another pod uses the app identity | Attacker deploys a pod in another namespace | FIC trusts one `namespace:serviceaccount` on one cluster issuer | Entra ID | `/whoami` shows `workload_identity` only for `ai-app/foundry-app` |
| S4 | Spoofing: pod borrows the node identity | Call IMDS `169.254.169.254` for the kubelet token | NetworkPolicy egress excludes `169.254.0.0/16` | Cilium | `k8s/base/networkpolicy.yaml` · OPA/Checkov on manifests |
| T1 | **Tampering**: malicious image | Tag re-pointed to a malicious image | Deploy **by digest**; `imagePullPolicy: Always`; ACR push only via JIT from the deploy job | Kubelet + ACR | OPA K1 · Checkov CKV_K8S_43 · deploy script refuses placeholders |
| T2 | Tampering: infra changed outside code | Portal change weakens a setting | Nightly drift + OPA on the live plan | `drift.yml` | Opens "Drift detected" issue |
| T3 | Tampering: state file edited or lost | State overwritten or deleted | Entra-only access (shared keys off), versioning, soft delete, `CanNotDelete` lock, `prevent_destroy` | Storage account | `infra/bootstrap` |
| T4 | Tampering: a PR weakens security | "Temporarily" enables public access | Checkov + OPA in CI and on the plan; ruleset requires all checks | GitHub ruleset | 7 required checks |
| R1 | **Repudiation**: who changed the cluster? | Unlogged kubectl change | `kube-audit-admin` logs every API write; local accounts disabled so every actor is an Entra identity | AKS diagnostics → Log Analytics | `AKSAuditAdmin` table |
| R2 | Forged telemetry | Leaked connection string used to inject fake logs | Local auth disabled on App Insights + Log Analytics; exporter uses Entra token | Azure Monitor ingestion | OPA T2 |
| I1 | **Information disclosure**: model reachable from internet | Public endpoint discovered | `public_network_access = false`; Private DNS | Foundry firewall | DNS resolves to 10.10.4.x in-cluster only; public call refused |
| I2 | Deployment IDs in a public repo | Subscription/tenant ID in logs or PR comments | Not committed; masked in logs; scrubbed from PR comments; plan files never uploaded | Workflows | `.gitignore` · gitleaks in pre-commit and CI |
| I3 | Secrets committed by mistake | Key pasted into code | gitleaks (pre-commit + full-history CI scan); nothing to commit anyway | CI | `secrets` check |
| D1 | **Denial of service**: runaway log cost | Bug floods logs | Dev: 1 GB/day cap | Log Analytics | tfvars |
| D2 | Model quota exhaustion | Abuse of `/chat` | Capacity per deployment (TPM); app returns 429; prompt size limit (413) | Foundry + app | app tests |
| E1 | **Elevation of privilege**: CI grants itself Owner | Malicious PR adds a role assignment | Plan identity is read-only; deploy identity's RBAC Admin is **ABAC-constrained** (7 allow-listed roles, service principals only) | Azure RBAC condition | OPA T8 (Owner/UAA/RBAC Admin by name or ID) |
| E2 | Container escape / root in pod | Exploit in the app | Non-root UID 10001, read-only FS, drop ALL, no privilege escalation, seccomp | **PSA `restricted`** (API server rejects violations) | OPA K2–K4 · Checkov |
| E3 | PR branch deploys to an environment | Branch names `environment: dev` | Environments accept **main only**; prod needs a reviewer | GitHub environments | `scripts/github-settings.sh` |
| E4 | Approved plan ≠ applied plan | Change lands between approval and apply | Plan **fingerprint** must match after approval | `deploy-prod.yml` | Job refuses on mismatch |

## 4. Blast radius: "what if X is compromised?"

| Compromised | Attacker gets | Attacker does NOT get |
|---|---|---|
| The app pod | Inference on one model deployment; read secrets in one vault; publish telemetry | Management of anything; the node identity (IMDS blocked); the Kubernetes API (no SA token mounted); lateral movement (default-deny) |
| A PR workflow | Read-only view of dev/prod RGs | Any write; any secret (none exist); any other repo's trust |
| The dev deploy identity | Control of the dev RG | Prod; Owner/UAA; roles for users or groups; anything outside `rg-aifz-dev` |
| A developer laptop | Whatever that human's Entra access allows | A key or kubeconfig that works elsewhere (none exist) |
| A leaked App Insights connection string | Nothing (ingestion requires Entra) | Ability to write or read telemetry |

## 5. Supply chain

- **Actions pinned to commit SHAs** (tag in a comment). A moved tag can't change what runs.
- **`GITHUB_TOKEN` starts with no permissions.** Each job requests only what it needs; checkout doesn't persist credentials.
- **Fork PRs get no OIDC token** (GitHub rule), and the plan job is skipped for them.
- **Images:** multi-stage build, slim base, OS packages upgraded at build, non-root, deployed by digest. Provider versions are pinned via `.terraform.lock.hcl`.
- **Tools pinned in CI:** Terraform 1.16.0, tflint v0.64.0, Checkov 3.3.10, OPA 1.21.0, gitleaks v8.30.1, actionlint 1.7.12.

## 6. Accepted risks and production extensions

| Residual risk | Why accepted here | Production extension |
|---|---|---|
| Pod egress to internet 443 is CIDR-scoped, not FQDN-scoped | FQDN policies need a paid add-on | Cilium FQDN policies (ACNS) or Azure Firewall with FQDN rules (ADR-0003, 0008) |
| ACR public endpoint exists (deny-by-default, JIT for CI) | GitHub-hosted runners are outside the VNet | Self-hosted runners in the VNet → ACR fully private (ADR-0006) |
| Dev AKS on Free tier, regional nodes | Cost and a subscription zone limitation | Prod is Standard + 3 zones, enforced by OPA T7 |
| Solo maintainer approves own prod deploys | One-person project | `prevent_self_review: true` with a team |
| No customer-managed keys | Microsoft-managed encryption is sufficient for this data | CMK in Key Vault for Foundry, storage and disks where regulation requires it |
| No image signing / admission verification | Digest pinning already prevents tag swaps | Notation/Cosign signing + Ratify/Gatekeeper verification |
| App identity client/object IDs appear in the public smoke-test log | They're identifiers, useless without a token from this cluster | Mask them in the workflow if policy requires |

## 7. Reporting

This is a portfolio project. If you notice a security issue, open a GitHub issue **without** exploit details, or contact the maintainer via the GitHub profile.
