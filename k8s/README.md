# Kubernetes manifests

Kustomize `base` + per-environment `overlays`. Environment values are **generated at deploy time from `terraform output`**, never committed.

```
k8s/
├── base/
│   ├── namespace.yaml       ai-app, Pod Security Admission "restricted" ENFORCED
│   ├── serviceaccount.yaml  foundry-app → azure.workload.identity/client-id (from Terraform)
│   ├── deployment.yaml      2 replicas · non-root 10001 · read-only FS · drop ALL · seccomp · probes
│   ├── service.yaml         ClusterIP only
│   ├── pdb.yaml             minAvailable 1 during node upgrades
│   └── networkpolicy.yaml   default-deny + explicit doors (below)
├── overlays/dev|prod/       replicas/resources; generated/*.env (git-ignored) fill the placeholders
└── tools/smoke-test.yaml    restricted, non-root curl Job for in-cluster end-to-end tests
```

## How values flow (nothing hard-coded, nothing committed)

```
terraform output ──▶ scripts/deploy-app.sh ──▶ overlays/<env>/generated/
   app_identity_client_id                        deploy.env  WORKLOAD_IDENTITY_CLIENT_ID ─▶ SA annotation
   private_endpoints_cidr                                    PRIVATE_ENDPOINTS_CIDR     ─▶ NetworkPolicy
   acr_login_server + pushed digest                          IMAGE (…@sha256:…)          ─▶ Deployment image
   foundry_openai_endpoint, deployment, appi     app.env     → ConfigMap aifz-app-config  ─▶ pod env
```

`deploy-params` is marked `config.kubernetes.io/local-config`, so kustomize uses it to fill placeholders and then **drops it from the output**. Only `aifz-app-config` reaches the cluster.

## Pod hardening

| Control | Setting | Enforced by |
|---|---|---|
| Non-root | `runAsNonRoot`, UID/GID 10001 | Manifest **and** PSA `restricted` (the API server rejects violations) |
| No privilege escalation | `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]` | Manifest + PSA |
| Syscall filtering | `seccompProfile: RuntimeDefault` | Manifest + PSA |
| Immutable container | `readOnlyRootFilesystem: true`; `/tmp` is a 64 Mi in-memory emptyDir | Manifest |
| No Kubernetes API token | `automountServiceAccountToken: false` (workload identity projects its own Azure-audience token) | Manifest |
| Immutable image | Deployed **by digest**; `imagePullPolicy: Always` re-authorizes the pull on every start | Manifest + deploy script checks |
| Availability | 2 replicas, spread across nodes, PDB, `maxUnavailable: 0` rolling updates | Manifest |
| Readiness = identity works | `/readyz` must obtain an Entra token before the pod gets traffic | Probe |

Checkov (Kubernetes): **92 passed, 0 failed, 0 skipped.**

## Network doors (default-deny, enforced by Cilium)

| From → To | Port | Why |
|---|---|---|
| any pod → kube-dns | 53 | Name resolution |
| app → Private Endpoint subnet | 443 | AI Foundry and Key Vault, privately |
| app → internet **except** private ranges and `169.254.0.0/16` | 443 | Entra ID token exchange + Azure Monitor ingestion |
| pods labelled `aifz/client=true` → app | 8080 | Smoke test / future internal callers |
| **everything else** | — | **Denied**, including other ports, pod-to-pod lateral movement, and **IMDS** |

Blocking **169.254.169.254 (IMDS)** means a compromised pod can't borrow the node's managed identity. It only ever holds its own workload identity. The documented limit: "internet 443" is CIDR-scoped, not FQDN-scoped (see ADR-0008).

## Deploy and test

```bash
make deploy-app ENV=dev     # build → JIT push → render (digest) → apply → rollout status
make smoke-test ENV=dev     # /healthz /readyz /whoami POST /chat from inside the cluster
make k8s-render ENV=dev     # inspect the exact manifest that was applied
```
