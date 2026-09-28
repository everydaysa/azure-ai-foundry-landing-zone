# ADR-0010: CI/CD with GitHub Actions: keyless, least-privilege, gated

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

The pipeline is the most privileged "user" of the platform. It must hold no long-lived secret, have the least permission each stage needs, and be unable to ship anything that fails a check.

## Decisions

| # | Workflow | Trigger | Azure identity (OIDC subject) | Can change Azure? |
|---|---|---|---|---|
| 1 | `ci.yml` | every PR + main | **none** | No |
| 2 | `plan.yml` | every PR (same repo) | `gh-plan` (`pull_request`) - Reader + AKS Cluster User + state lock | No |
| 3 | `deploy-dev.yml` | merge to main | `gh-dev` (`environment:dev`) | dev RG only |
| 4 | `deploy-prod.yml` | manual, main only, **reviewer approval** | plan: `gh-plan` (`ref:refs/heads/main`); apply: `gh-prod` (`environment:prod`) | prod RG only |
| 5 | `drift.yml` | nightly | `gh-plan` (`ref:refs/heads/main`) | No |

1. **No secrets exist.** Every Azure call uses GitHub's OIDC token, exchanged for a short-lived Entra token by a federated credential whose *subject* pins the repository and context. The repository holds only identifiers (GitHub variables), and they are masked in the public logs.
2. **Environments carry the boundary.** `dev` and `prod` accept deployments **from main only**. Without that branch policy, any branch could claim `environment:dev` and receive the dev identity.
3. **Policy gates are in the deploy path**, not just in CI: OPA on the plan before `apply`, and OPA on the rendered manifests before `kubectl apply`.
4. **What you approve is what runs (prod).** The reviewer sees a plan with a fingerprint (the sorted address/action list). After approval, the job re-plans and refuses if the fingerprint differs. No plan file is uploaded, because artifacts on a public repo would expose resource details.
5. **Supply chain:** every third-party action is **pinned to a commit SHA** (with its tag as a comment); `GITHUB_TOKEN` defaults to no permissions and each job asks for the minimum; `persist-credentials: false`; fork PRs never receive an OIDC token.
6. **Drift + continuous compliance:** the nightly plan contains every live resource, so running OPA on it re-audits the whole environment. The result is one issue per environment, closed automatically when clean.
7. **`main` is protected by a ruleset** (`scripts/github-settings.sh`): PR-only, no force-push, and all CI + plan checks required.

## Alternatives considered

| Option | Why not |
|---|---|
| Service principal + client secret in GitHub Secrets | A long-lived secret to leak and rotate; contradicts ADR-0001 |
| One identity for all stages | A PR could then change production |
| Upload `tfplan` as an artifact and apply it | Exact, but the plan file would be downloadable from a public repo |
| Self-hosted runners in the VNet | Would remove the ACR JIT rule and `command invoke`, but adds a VM fleet to patch. **Production extension.** |

## Consequences

- ✅ The pipeline has no secret to steal, and a compromised PR can at most *read* the environment.
- ✅ Every security decision in ADR-0001 to 0009 is re-checked on every change and every night.
- ⚠️ A solo maintainer approves their own prod deploys (`prevent_self_review: false`). On a team this flips to `true`.
- ⚠️ After teardown, the nightly drift job reports everything as missing. Disable it with `gh workflow disable drift.yml`.
