# ADR-0008: Kubernetes workload hardening and network policy

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

The app runs in a shared cluster and holds an identity that can call the model. If the pod were compromised, the damage should be limited to that one identity, with no root, no node credentials, no lateral movement and no arbitrary egress.

## Decisions

1. **Pod Security Admission `restricted` is enforced** on the `ai-app` namespace. The API server rejects non-compliant pods, whatever their manifests say.
2. **The pod security context** runs as non-root UID 10001, with a read-only root filesystem, all capabilities dropped, no privilege escalation, and seccomp `RuntimeDefault`.
3. **No Kubernetes API token** is mounted (`automountServiceAccountToken: false`). Workload identity projects its own Azure-audience token.
4. **Images are deployed by digest** and pulled with `imagePullPolicy: Always`. The deploy script refuses to apply a manifest with a placeholder image.
5. **Default-deny NetworkPolicy**, then explicit egress: DNS; 443 to the Private Endpoint subnet; 443 to public addresses **excluding** RFC 1918, CGNAT and link-local (**blocks IMDS**). Ingress only from pods labelled `aifz/client=true`.
6. **Environment values are generated from `terraform output` at deploy time** (git-ignored). The repository holds no deployment identifiers.

## Alternatives considered

| Option | Why not (now) |
|---|---|
| FQDN egress policies (Cilium + Advanced Container Networking Services) | Tightest (`login.microsoftonline.com`, `*.applicationinsights.azure.com` only), but it's a paid add-on. **Production extension.** |
| Egress through Azure Firewall | See ADR-0003: the production path for FQDN filtering at the network edge |
| Sealed Secrets / Key Vault CSI for config | There are no secrets to protect: the config is identifiers and endpoints only |

## Consequences

- ✅ A compromised pod has one Entra identity (inference-only on Foundry, read-only on Key Vault), no node identity, no Kubernetes API access, and no network path except 443 outward.
- ✅ Identical manifests for every environment; only generated values differ.
- ⚠️ Egress to the internet on 443 isn't restricted by hostname. A compromised pod could reach arbitrary HTTPS sites, but it carries no reusable secret to exfiltrate.
