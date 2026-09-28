#!/usr/bin/env bash
# ─── Evaluate the OPA policies against real artifacts ─────────────────────
#
#   scripts/opa-eval.sh plan dev   # the saved Terraform plan (make plan ENV=dev first)
#   scripts/opa-eval.sh k8s  dev   # the rendered Kubernetes manifests
#
# `opa test` proves the rules are correct; this script proves the THINGS WE
# DEPLOY comply with them. Exit code 1 = at least one violation.
set -euo pipefail

MODE="${1:?usage: $0 plan|k8s [env]}"
ENV="${2:-dev}"
ROOT="$(git rev-parse --show-toplevel)"
POLICY="$ROOT/policy/opa"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Print every deny message for one input file; return 1 if there were any.
evaluate() { # <package> <input-file>
  local out
  out="$(opa eval --format raw --data "$POLICY" --input "$2" \
    "concat(\"\n\", sort(data.$1.deny))")"
  [ -z "$out" ] && return 0
  while IFS= read -r line; do echo "  ✗ $line"; done <<<"$out"
  return 1
}

case "$MODE" in
  plan)
    TF_DIR="$ROOT/infra/envs/$ENV"
    [ -f "$TF_DIR/tfplan" ] || { echo "No saved plan in $TF_DIR - run 'make plan ENV=$ENV' first."; exit 1; }
    terraform -chdir="$TF_DIR" show -json tfplan >"$WORK/plan.json"
    echo "==> OPA: Terraform plan ($ENV) - $(grep -o '"address"' "$WORK/plan.json" | wc -l | tr -d ' ') addresses"
    if evaluate terraform "$WORK/plan.json"; then
      echo "  ✓ no violations"
    else
      exit 1
    fi
    ;;

  k8s)
    # Render the overlay when deploy-app has generated its values; otherwise
    # the base (placeholders are valid for policy purposes, e.g. CI).
    if [ -f "$ROOT/k8s/overlays/$ENV/generated/deploy.env" ]; then
      SRC="k8s/overlays/$ENV"
    else
      SRC="k8s/base"
    fi
    {
      kubectl kustomize "$ROOT/$SRC"
      for f in "$ROOT"/k8s/tools/*.yaml; do echo "---"; cat "$f"; done
    } >"$WORK/all.yaml"

    # One YAML document per file (OPA reads a single document per input).
    awk -v dir="$WORK" 'BEGIN { n = 0 }
      /^---[[:space:]]*$/ { n++; next }
      { f = sprintf("%s/doc-%03d.yaml", dir, n); print > f }' "$WORK/all.yaml"

    echo "==> OPA: Kubernetes manifests ($SRC + k8s/tools)"
    failed=0 checked=0
    for doc in "$WORK"/doc-*.yaml; do
      grep -q '^kind:' "$doc" || continue
      checked=$((checked + 1))
      evaluate kubernetes "$doc" || failed=1
    done
    if [ "$failed" -eq 0 ]; then
      echo "  ✓ $checked objects, no violations"
    else
      exit 1
    fi
    ;;

  *)
    echo "usage: $0 plan|k8s [env]"; exit 2 ;;
esac
