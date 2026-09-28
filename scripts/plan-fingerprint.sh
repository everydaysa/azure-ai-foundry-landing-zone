#!/usr/bin/env bash
# ─── Fingerprint of a saved Terraform plan ────────────────────────────────
#
#   scripts/plan-fingerprint.sh prod   ->  e.g. 3f9c2a1b7d4e8f60
#
# SHA-256 of the sorted list of (resource address, actions) the plan would
# change. deploy-prod.yml shows the reviewer a plan with this fingerprint and
# refuses to apply if the re-plan after approval has a different one.
set -euo pipefail

ENV="${1:?usage: $0 <env>}"
ROOT="$(git rev-parse --show-toplevel)"

terraform -chdir="$ROOT/infra/envs/$ENV" show -json tfplan |
  jq -cS '[.resource_changes[]?
           | select(.change.actions != ["no-op"] and .change.actions != ["read"])
           | {address, actions: .change.actions}]
          | sort_by(.address)' |
  shasum -a 256 | cut -c1-16
