#!/usr/bin/env bash
# ─── Repository guardrails as code (run once; safe to re-run) ─────────────
#
#   scripts/github-settings.sh
#
#   environment dev   deployments only from main
#   environment prod  deployments only from main + a required reviewer (you)
#   ruleset "main"    no direct pushes, no force-push, no deletion;
#                     merge only via PR with every CI + plan check green
#
# Why the branch policy matters: Entra ID trusts the OIDC subject
# "environment:dev". Without the policy, any branch could name that
# environment and receive the dev identity.
set -euo pipefail

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
ME_ID="$(gh api user -q .id)"
ME="$(gh api user -q .login)"
echo "repo=$REPO reviewer=$ME"

main_only() { # <env>
  gh api -X POST "repos/$REPO/environments/$1/deployment-branch-policies" \
    -f name=main -f type=branch >/dev/null 2>&1 || true   # already present = fine
}

echo "==> environment dev (main only)"
gh api -X PUT "repos/$REPO/environments/dev" --input - >/dev/null <<JSON
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
main_only dev

echo "==> environment prod (main only + required reviewer)"
# prevent_self_review=false: this is a one-person project. On a team, set it
# to true so the person who triggered a deploy can't approve it.
gh api -X PUT "repos/$REPO/environments/prod" --input - >/dev/null <<JSON
{"wait_timer": 0, "prevent_self_review": false,
 "reviewers": [{"type": "User", "id": $ME_ID}],
 "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
main_only prod

echo "==> ruleset on the default branch"
RULESET="$(cat <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": true,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": true}},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": true,
      "required_status_checks": [
        {"context": "terraform", "integration_id": 15368},
        {"context": "policy", "integration_id": 15368},
        {"context": "app", "integration_id": 15368},
        {"context": "secrets", "integration_id": 15368},
        {"context": "workflows", "integration_id": 15368},
        {"context": "plan (dev)", "integration_id": 15368},
        {"context": "plan (prod)", "integration_id": 15368}]}}
  ]
}
JSON
)"
ID="$(gh api "repos/$REPO/rulesets" -q '.[] | select(.name=="main") | .id')"
if [ -n "$ID" ]; then
  gh api -X PUT "repos/$REPO/rulesets/$ID" --input - >/dev/null <<<"$RULESET"
else
  gh api -X POST "repos/$REPO/rulesets" --input - >/dev/null <<<"$RULESET"
fi

echo "==> result"
gh api "repos/$REPO/environments" -q '.environments[] | "\(.name): rules=\([.protection_rules[].type] | join(","))"'
gh api "repos/$REPO/rulesets" -q '.[] | "ruleset \(.name): \(.enforcement)"'
