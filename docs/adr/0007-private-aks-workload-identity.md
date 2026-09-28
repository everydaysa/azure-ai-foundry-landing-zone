# ADR-0007: Private AKS with workload identity

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

The application must call AI Foundry, Key Vault and App Insights without secrets, and the platform must have no public PaaS or control-plane endpoints. The Kubernetes API server is the most sensitive endpoint in the design.

## Decisions

| Topic | Decision | Alternative rejected |
|---|---|---|
| API server exposure | **Private cluster**; operators and CI use `az aks command invoke` (Entra-authenticated, via ARM) | Public API with authorized IP ranges: simpler `kubectl`, but still a public endpoint |
| Cluster auth | Entra ID + Azure RBAC, `local_account_disabled = true` | Static admin kubeconfig |
| Workload → Azure | **Workload identity**: OIDC issuer + federated credential bound to one ServiceAccount | Secrets in Kubernetes, or pod-managed identity (deprecated) |
| Control-plane identity | User-assigned, with Network Contributor on the VNet granted **before** creation | System-assigned (exists too late to be granted subnet access) |
| Networking | Azure CNI Overlay + Cilium; egress via NAT Gateway | kubenet (retiring); load-balancer egress |
| Nodes | AzureLinux, ephemeral OS, host encryption, autoscaled; dev 2–3 × D2ds_v4 regional, prod 3–5 × D2ds_v4 in zones 1–3 (see Consequences) | Managed OS disks; single node |
| Admission | Azure Policy add-on (Gatekeeper/OPA), which pairs with OPA checks in CI | None |
| Logs | `kube-audit-admin` (writes only) + `guard` + autoscaler | `kube-audit` (all reads too): far more volume and cost |

## Accepted trade-offs

| Checkov | Trade-off | Production extension |
|---|---|---|
| CKV_AZURE_6 | N/A for private clusters | — |
| CKV_AZURE_170 | Free tier in dev (cost) | Prod uses Standard; enforced by an OPA policy on the prod plan |
| CKV_AZURE_117 | Platform-managed disk keys (+ host encryption) | Disk Encryption Set with a customer-managed key |
| CKV_AZURE_232 | Single node pool (dev cost) | Separate user pool; system pool with `only_critical_addons_enabled = true` |

## Consequences

- ✅ No Kubernetes, Azure or model credentials are stored anywhere.
- ✅ The API server is unreachable from the internet. Every admin action is an Entra-authenticated ARM call, logged in the Activity Log and in kube-audit-admin.
- ⚠️ `kubectl port-forward` from a laptop isn't available. The demo uses `az aks command invoke`, or an in-cluster `curl`, to exercise the app.
- ⚠️ `sku_tier = "Free"` in dev (no API SLA); prod uses `Standard`.
- ⚠️ **Dev nodes are regional, not zone-spread.** On 2026-09-27, AKS rejected zonal placement in eastus2 for this subscription (`AvailabilityZoneNotSupported`, "supported zones are ''"), although `az vm list-skus` reported zones 1–3 with no restrictions for `Standard_D2ds_v5`. Zones are therefore a per-environment input (`aks_availability_zones`): dev = `[]`, prod = `["1","2","3"]`. Flipping dev back is a one-line change once the subscription's AKS zonal capacity is available.
- ⚠️ **Node size follows available quota.** The next apply failed with `ErrCode_InsufficientVCPUQuota`: 0 vCPUs for the DDSv5 family in eastus2 (new pay-as-you-go subscription), while DDSv4 and most other D-series families had 10 (the regional total is also 10). Both environments therefore use `Standard_D2ds_v4` (2 vCPU, 75 GiB temp disk, which keeps ephemeral OS + host encryption). The zero DDSv5 quota is also the most likely cause of the earlier "supported zones are ''" error. **Lesson codified in the runbook:** check `az vm list-usage` for the target family before the first apply (need ≥ 8 vCPUs: 3 nodes × 2 + 1 surge node).
