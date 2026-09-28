#!/usr/bin/env bash
# ─── Prove the security controls: PASS/FAIL per control ───────────────────
#
#   scripts/security-test.sh dev        (make security-test ENV=dev)
#
# Positive tests (smoke test) show the app WORKS. These show what must NOT
# be possible, from two vantage points:
#   control plane (your laptop, az)  : keys disabled, no public access, private cluster
#   inside the cluster (command invoke): private DNS, IMDS blocked, only 443 out,
#                                        unlabelled pods can't reach the app
# Exit code 1 if any control fails.
set -euo pipefail

ENV="${1:-dev}"
ROOT="$(git rev-parse --show-toplevel)"
TF_DIR="$ROOT/infra/envs/$ENV"
RG="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
AKS="$(terraform -chdir="$TF_DIR" output -raw aks_name)"
AI="$(az cognitiveservices account list -g "$RG" --query "[0].name" -o tsv)"
LAW="$(az monitor log-analytics workspace list -g "$RG" --query "[0].name" -o tsv)"

results=()
check() { # <name> <actual> <expected>   (case-insensitive: az prints booleans as True/False)
  if [ "$(tr '[:upper:]' '[:lower:]' <<<"$2")" = "$(tr '[:upper:]' '[:lower:]' <<<"$3")" ]; then results+=("PASS  $1: $2"); else results+=("FAIL  $1: got '$2', expected '$3'"); fi
}

echo "==> Control plane checks (az)"
check "Foundry API keys cannot authenticate (local auth disabled)" \
  "$(az cognitiveservices account show -g "$RG" -n "$AI" --query properties.disableLocalAuth -o tsv)" "true"
check "Foundry public network access disabled" \
  "$(az cognitiveservices account show -g "$RG" -n "$AI" --query properties.publicNetworkAccess -o tsv)" "Disabled"
check "AKS API server is private" \
  "$(az aks show -g "$RG" -n "$AKS" --query apiServerAccessProfile.enablePrivateCluster -o tsv)" "true"
check "AKS local (static kubeconfig) accounts disabled" \
  "$(az aks show -g "$RG" -n "$AKS" --query disableLocalAccounts -o tsv)" "true"
check "AKS workload identity enabled" \
  "$(az aks show -g "$RG" -n "$AKS" --query securityProfile.workloadIdentity.enabled -o tsv)" "true"
check "Log Analytics rejects key-based ingestion" \
  "$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query features.disableLocalAuth -o tsv)" "true"
check "Key Vault public network access disabled" \
  "$(az keyvault list -g "$RG" --query "[0].properties.publicNetworkAccess" -o tsv)" "Disabled"

echo "==> In-cluster probes (az aks command invoke, ~30-60 s)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/scripts/in-pod/probes.py" "$ROOT/k8s/tools/netpol-probe.yaml" "$WORK/"
cd "$WORK"
probe_out="$(az aks command invoke -g "$RG" -n "$AKS" --file . -o tsv --query logs --command '
  kubectl -n ai-app exec -i deploy/aifz-app -- python - < probes.py
  kubectl -n ai-app delete job aifz-netpol-probe --ignore-not-found --wait=true >/dev/null
  kubectl apply -f netpol-probe.yaml >/dev/null
  kubectl -n ai-app wait --for=condition=complete job/aifz-netpol-probe --timeout=120s >/dev/null \
    && kubectl -n ai-app logs job/aifz-netpol-probe \
    || echo "FAIL  NetworkPolicy probe did not complete"
  kubectl -n ai-app delete job aifz-netpol-probe --wait=false >/dev/null')"
while IFS= read -r line; do
  case "$line" in PASS*|FAIL*) results+=("$line") ;; esac
done <<<"$probe_out"

echo
printf '%s\n' "${results[@]}"
fails="$(printf '%s\n' "${results[@]}" | grep -c '^FAIL' || true)"
echo
if [ "$fails" -eq 0 ]; then
  echo "SECURITY TESTS PASSED (${#results[@]} controls)"
else
  echo "SECURITY TESTS FAILED: $fails of ${#results[@]} controls"
  exit 1
fi
