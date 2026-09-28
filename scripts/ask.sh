#!/usr/bin/env bash
# ─── Ask the model a question, from your laptop ───────────────────────────
#
#   scripts/ask.sh dev "Explain a private endpoint in one sentence."
#   make ask ENV=dev PROMPT="..."
#
# Your laptop has no network path to the app, the API server or AI Foundry
# (by design). `az aks command invoke` asks Azure to run kubectl INSIDE the
# private cluster, authorized by your Entra identity. kubectl exec runs a tiny
# client in the app pod, which calls the app, which calls the model with its
# workload identity over the private endpoint.
set -euo pipefail

ENV="${1:-dev}"
PROMPT="${2:?usage: $0 <env> \"your question\"}"
ROOT="$(git rev-parse --show-toplevel)"
TF_DIR="$ROOT/infra/envs/$ENV"
RG="$(terraform -chdir="$TF_DIR" output -raw resource_group_name)"
AKS="$(terraform -chdir="$TF_DIR" output -raw aks_name)"
B64="$(printf '%s' "$PROMPT" | base64 | tr -d '\n')"

echo "Q: $PROMPT"
echo "   (via az aks command invoke → $AKS → aifz-app → AI Foundry; ~20-40 s)"
echo
cd "$ROOT/scripts/in-pod"
az aks command invoke -g "$RG" -n "$AKS" --file ask.py -o tsv --query logs \
  --command "kubectl -n ai-app exec -i deploy/aifz-app -- env PROMPT_B64=$B64 python - < ask.py"
