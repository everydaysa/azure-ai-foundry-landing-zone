#!/usr/bin/env bash
# ─── Build, push and deploy the app to one environment ────────────────────
#
#   scripts/deploy-app.sh dev
#
#   1. read everything from `terraform output`   (nothing hard-coded, nothing committed)
#   2. build the image for linux/amd64            (AKS nodes)
#   3. push it through a JUST-IN-TIME ACR firewall opening for THIS machine's IP,
#      closed again on exit - even on failure (trap)
#   4. render the kustomize overlay with the image DIGEST (immutable)
#   5. apply via `az aks command invoke`         (private API server: no VPN, no kubeconfig)
#   6. wait for the rollout
#
# The same steps run in the GitHub Actions deploy workflow (Step 14).
set -euo pipefail

ENV="${1:-dev}"
ROOT="$(git rev-parse --show-toplevel)"
TF_DIR="$ROOT/infra/envs/$ENV"
OVERLAY="$ROOT/k8s/overlays/$ENV"
WORK="$(mktemp -d)"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
out() { terraform -chdir="$TF_DIR" output -raw "$1"; }

[[ -d "$TF_DIR" && -d "$OVERLAY" ]] || { echo "unknown environment: $ENV"; exit 1; }
for tool in terraform az docker kubectl python3 curl; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool"; exit 1; }
done

log "Reading terraform outputs for '$ENV'"
RG="$(out resource_group_name)"
AKS="$(out aks_name)"
ACR="$(out acr_name)"
LOGIN_SERVER="$(out acr_login_server)"
CLIENT_ID="$(out app_identity_client_id)"
ENDPOINT="$(out foundry_openai_endpoint)"
PE_CIDR="$(out private_endpoints_cidr)"
AI_CONN="$(out application_insights_connection_string)"
DEPLOYMENT="$(terraform -chdir="$TF_DIR" output -json foundry_deployment_names | python3 -c 'import json,sys; print(json.load(sys.stdin)[0])')"
TAG="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- app || echo -dirty)"
echo "cluster=$AKS registry=$ACR deployment=$DEPLOYMENT tag=$TAG"

log "Opening the registry firewall just-in-time for this machine"
MY_IP="$(curl -fsS https://api.ipify.org)"
close_firewall() {
  echo "closing registry firewall for $MY_IP"
  az acr network-rule remove -n "$ACR" --ip-address "$MY_IP" -o none 2>/dev/null || true
  rm -rf "$WORK"
}
trap close_firewall EXIT
az acr network-rule add -n "$ACR" --ip-address "$MY_IP" -o none
echo "rule added for $MY_IP - waiting for it to take effect"
for i in $(seq 1 30); do
  if az acr login -n "$ACR" >/dev/null 2>&1; then echo "registry reachable (after ~$((i * 5)) s)"; break; fi
  [[ $i -eq 30 ]] && { echo "registry still unreachable after 150 s"; exit 1; }
  sleep 5
done

log "Building and pushing $LOGIN_SERVER/aifz-app:$TAG (linux/amd64)"
docker buildx build --platform linux/amd64 --provenance=false \
  -t "$LOGIN_SERVER/aifz-app:$TAG" --push "$ROOT/app"
DIGEST="$(az acr repository show -n "$ACR" --image "aifz-app:$TAG" --query digest -o tsv)"
IMAGE="$LOGIN_SERVER/aifz-app@$DIGEST"
echo "image pinned by digest: $IMAGE"

close_firewall
trap - EXIT
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log "Rendering k8s/overlays/$ENV"
mkdir -p "$OVERLAY/generated"
cat > "$OVERLAY/generated/deploy.env" <<EOF
IMAGE=$IMAGE
WORKLOAD_IDENTITY_CLIENT_ID=$CLIENT_ID
PRIVATE_ENDPOINTS_CIDR=$PE_CIDR
EOF
cat > "$OVERLAY/generated/app.env" <<EOF
FOUNDRY_OPENAI_ENDPOINT=$ENDPOINT
FOUNDRY_DEPLOYMENT=$DEPLOYMENT
APPLICATIONINSIGHTS_CONNECTION_STRING=$AI_CONN
SERVICE_NAME=aifz-app-$ENV
EOF
kubectl kustomize "$OVERLAY" > "$WORK/manifest.yaml"
grep -q 'PLACEHOLDER' "$WORK/manifest.yaml" && { echo "unreplaced placeholder in manifest"; exit 1; }
grep -q '@sha256:0000000000' "$WORK/manifest.yaml" && { echo "placeholder digest in manifest"; exit 1; }
echo "rendered $(grep -c '^kind:' "$WORK/manifest.yaml") objects"

log "Applying to $AKS (private cluster, via az aks command invoke)"
( cd "$WORK" && az aks command invoke -g "$RG" -n "$AKS" --file manifest.yaml \
    --command "kubectl apply -f manifest.yaml && kubectl -n ai-app rollout status deployment/aifz-app --timeout=300s" \
    --query logs -o tsv )

log "Deployed $IMAGE to $ENV. Run: scripts/smoke-test.sh $ENV"
