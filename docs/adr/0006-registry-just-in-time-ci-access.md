# ADR-0006: Container registry with just-in-time CI access

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

AKS must pull images privately. The CD pipeline runs on **GitHub-hosted runners**, which live on the internet and have no fixed IP, so a fully private registry can't receive their pushes.

| Option | Security | Cost / complexity |
|---|---|---|
| Public registry with a static allow-list | Weak: runner IP ranges are huge and shared | Low |
| **Deny-by-default + just-in-time IP rule** | Closed at rest; opened for one IP for minutes; identity still required | Low |
| Fully private + self-hosted runner in the VNet | Strongest | A runner VM or ACA job to build, patch and pay for |
| Fully private, manual pushes | Strong | No automated CD |

## Decision

Use a **Premium** registry with `default_action = "Deny"`, **no standing IP rules**, a Private Endpoint for AKS, and `admin_enabled = false`. The CD workflow:

1. logs in to Azure with OIDC (dev deploy identity, AcrPush),
2. adds **its own runner IP** to the registry firewall,
3. pushes the image (by digest) with an Entra token,
4. removes the IP rule in an `always()` step, even if the push fails.

Terraform declares "no IP rules", so any rule left behind by an interrupted run is removed on the next `apply`.

## Consequences

- ✅ At rest, the registry's public endpoint admits no one.
- ✅ Even while it's open, pushes need a valid Entra token with AcrPush; the IP rule alone grants nothing.
- ✅ Every login and push is logged with the identity and source IP.
- ⚠️ The public endpoint technically exists (Checkov CKV_AZURE_139). **Production extension:** self-hosted runners inside the VNet, then `public_network_access_enabled = false` and `export_policy_enabled = false`.
- ⚠️ Quarantine isn't enabled; images are scanned in CI (Trivy) and at rest (Defender for Containers) instead.
