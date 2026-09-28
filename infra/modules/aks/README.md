# Module: `aks`

A private, Entra-only AKS cluster whose workloads authenticate to Azure with **workload identity**, never secrets.

```
you / CI ──(Entra token; `az aks command invoke`)──▶ API server (PRIVATE IP only)
                                                      Entra ID + Azure RBAC · local accounts OFF
aks-<prefix>
 ├─ node pool "system": AzureLinux · D*ds size + zones per environment (dev: D2ds_v4 ×2–3, regional) · ephemeral OS · host encryption · no public IPs
 │    CNI Overlay + Cilium (eBPF, NetworkPolicy) ── egress ──▶ NAT Gateway (network module)
 ├─ OIDC issuer ──▶ federated credential ──▶ id-<prefix>-app   (the app's Azure identity)
 │                  subject = system:serviceaccount:ai-app:foundry-app   ← only this SA
 ├─ add-ons: Azure Policy (Gatekeeper/OPA) · Key Vault CSI (rotation) · Container Insights (MSI auth, DCR)
 ├─ control-plane logs: kube-audit-admin · guard · cluster-autoscaler ─▶ central workspace
 └─ kubelet identity ──(AcrPull, granted by the stack)──▶ ACR via Private Endpoint
```

## How workload identity works (the "zero keys" mechanism)

```
Pod (ServiceAccount ai-app/foundry-app)
  │ 1. kubelet projects a short-lived JWT signed by the cluster's OIDC issuer
  ▼
Entra ID ── 2. checks the federated credential: issuer == this cluster AND subject == that SA
  │ 3. issues an access token for id-<prefix>-app (≈1 h)
  ▼
AI Foundry / Key Vault / App Insights ── 4. RBAC: OpenAI User / Secrets User / Metrics Publisher
```

No secret is stored anywhere. A different ServiceAccount, or the same one in another cluster, gets nothing.

## Security properties

| Area | Setting |
|---|---|
| API server | `private_cluster_enabled = true`, no public FQDN; reached via `az aks command invoke` (Entra-authenticated) |
| AuthN / AuthZ | Entra ID + Azure RBAC for Kubernetes; `local_account_disabled = true` (no static admin kubeconfig) |
| Workload auth | OIDC issuer + workload identity; one federated credential bound to one ServiceAccount |
| Nodes | AzureLinux, ephemeral OS disk, **host encryption**, no public IPs, 3 availability zones, autoscaling |
| Network | Azure CNI Overlay, **Cilium** data plane + NetworkPolicy, egress only via the NAT Gateway |
| Admission control | Azure Policy add-on (Gatekeeper / OPA) |
| Secrets | Key Vault Secrets Store CSI driver with rotation |
| Patching | `automatic_upgrade_channel = "patch"`, `node_os_upgrade_channel = "NodeImage"`, Image Cleaner |
| Observability | Container Insights via a Data Collection Rule with managed-identity auth; control-plane audit logs |
| Least-privilege control plane | User-assigned identity with **Network Contributor on the VNet only**, granted *before* the cluster exists |

Checkov: 17 passed, 4 skipped with justification (ADR-0007):

| Skipped | Reason |
|---|---|
| CKV_AZURE_6 authorized IP ranges | Private cluster: there's no public API endpoint to restrict |
| CKV_AZURE_170 paid SKU | Tier is per environment: Free in dev, Standard in prod (enforced by OPA) |
| CKV_AZURE_117 disk encryption set | Platform-managed keys + host encryption; CMK disk encryption set is the regulated extension |
| CKV_AZURE_232 critical-addons-only system pool | Single pool for dev cost; production adds a user pool |

## Prerequisite (one-time, per subscription)

Host encryption must be enabled on the subscription before `apply`:

```bash
az feature register --namespace Microsoft.Compute --name EncryptionAtHost
az feature show --namespace Microsoft.Compute --name EncryptionAtHost --query properties.state -o tsv   # wait for "Registered"
az provider register --namespace Microsoft.Compute
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix`, `location`, `resource_group_name`, `tenant_id` | Placement | — |
| `vnet_id`, `aks_nodes_subnet_id` | From `network` | — |
| `log_analytics_workspace_id` | From `monitoring` | — |
| `kubernetes_version` | major.minor, `null` = AKS default | `null` |
| `sku_tier` | `Free` (dev) / `Standard` (SLA) | `Standard` |
| `node_vm_size`, `node_min_count`, `node_max_count`, `node_os_disk_size_gb`, `availability_zones` | Node pool | `Standard_D2ds_v5`, 2, 3, 64, `["1","2","3"]` |
| `app_namespace`, `app_service_account` | Workload identity binding | `ai-app`, `foundry-app` |
| `tags` | Tags | `{}` |

## Outputs

`id`, `name`, `oidc_issuer_url`, `kubelet_object_id`, `app_identity_client_id`, `app_identity_principal_id`, `app_namespace`, `app_service_account`, `node_resource_group`

## Tests

```bash
terraform init -backend=false && terraform test
```

These check: the private, Entra-only API server; workload identity bound to exactly one ServiceAccount and this cluster's issuer; hardened nodes; Overlay + Cilium + NAT egress; the Policy and monitoring add-ons, with the DCR associated; and node-count validation.

## Operating a private cluster

```bash
# Any kubectl command, from anywhere, with your Entra identity (no VPN needed):
az aks command invoke -g rg-aifz-dev -n aks-aifz-dev --command "kubectl get pods -A"

# Apply manifests from a local folder:
az aks command invoke -g rg-aifz-dev -n aks-aifz-dev --command "kubectl apply -k ." --file ./k8s/overlays/dev
```
