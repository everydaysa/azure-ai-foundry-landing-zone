#!/usr/bin/env bash
# ─── End-to-end smoke test, run INSIDE the cluster ────────────────────────
#
#   scripts/smoke-test.sh dev
#
# Launches k8s/tools/smoke-test.yaml (a restricted, non-root curl Job that the
# NetworkPolicies allow to reach the app) and prints its output:
#   /healthz  /readyz  /whoami  POST /chat  ->  "SMOKE TEST PASSED"
set -euo pipefail

ENV="${1:-dev}"
ROOT="$(git rev-parse --show-toplevel)"
TF_DIR="$ROOT/infra/envs/$ENV"
RG="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
AKS="$(terraform -chdir="$TF_DIR" output -raw aks_name)"

cd "$ROOT/k8s/tools"
az aks command invoke -g "$RG" -n "$AKS" --file smoke-test.yaml --command '
  kubectl -n ai-app delete job aifz-smoke-test --ignore-not-found --wait=true >/dev/null
  kubectl apply -f smoke-test.yaml >/dev/null
  if kubectl -n ai-app wait --for=condition=complete job/aifz-smoke-test --timeout=180s >/dev/null; then
    kubectl -n ai-app logs job/aifz-smoke-test
  else
    echo "SMOKE TEST FAILED"; kubectl -n ai-app logs job/aifz-smoke-test || true
    kubectl -n ai-app get pods -o wide; exit 1
  fi' --query logs -o tsv
