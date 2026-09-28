# ─── AKS baseline (ADR-0007) ──────────────────────────────────────────────
package terraform

import rego.v1

# Settings that must hold in EVERY environment: attribute -> required value.
aks_required := {
	"private_cluster_enabled": true,
	"private_cluster_public_fqdn_enabled": false,
	"local_account_disabled": true,
	"oidc_issuer_enabled": true,
	"workload_identity_enabled": true,
	"azure_policy_enabled": true,
}

deny contains msg if {
	some r in resources
	r.type == "azurerm_kubernetes_cluster"
	some attr, want in aks_required
	not after(r)[attr] == want
	msg := sprintf("%s: %s must be %v", [r.address, attr, want])
}

# Production control plane needs the uptime SLA (Standard tier). Dev runs on
# Free to save cost - this is the check promised when CKV_AZURE_170 was
# skipped in the AKS module. The environment comes from the resource's own
# `environment` tag; removing the tag to dodge this rule fails tags.rego.
deny contains msg if {
	some r in resources
	r.type == "azurerm_kubernetes_cluster"
	tags_of(r).environment == "prod"
	not after(r).sku_tier == "Standard"
	msg := sprintf("%s: prod AKS must use sku_tier \"Standard\" (uptime SLA), got %v", [r.address, object.get(after(r), "sku_tier", null)])
}
