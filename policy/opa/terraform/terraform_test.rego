# Unit tests for the Terraform plan rules:  opa test policy/opa -v
# Each rule gets a "compliant passes" and a "violation is denied" case,
# built from tiny hand-written plan fragments (no Azure, no Terraform).
package terraform_test

import rego.v1

import data.terraform

tags(env) := {"project": "aifz", "environment": env, "managed_by": "terraform"}

res(t, after) := {
	"address": sprintf("%s.test", [t]),
	"mode": "managed",
	"type": t,
	"change": {"actions": ["create"], "after": after},
}

plan(rs) := {"resource_changes": rs}

denied_with(inp, text) if {
	msgs := terraform.deny with input as inp
	some m in msgs
	contains(m, text)
}

clean(inp) if {
	msgs := terraform.deny with input as inp
	count(msgs) == 0
}

# ─── Fixtures: compliant resources ────────────────────────────────────────
foundry := {
	"local_auth_enabled": false,
	"public_network_access_enabled": false,
	"outbound_network_access_restricted": true,
	"tags": tags("dev"),
}

aks(env, tier) := {
	"private_cluster_enabled": true,
	"private_cluster_public_fqdn_enabled": false,
	"local_account_disabled": true,
	"oidc_issuer_enabled": true,
	"workload_identity_enabled": true,
	"azure_policy_enabled": true,
	"sku_tier": tier,
	"tags": tags(env),
}

# ─── Whole compliant plan ─────────────────────────────────────────────────
test_compliant_plan_has_no_denials if {
	clean(plan([
		res("azurerm_cognitive_account", foundry),
		res("azurerm_key_vault", {"public_network_access_enabled": false, "tags": tags("dev")}),
		res("azurerm_log_analytics_workspace", {"local_authentication_enabled": false, "tags": tags("dev")}),
		res("azurerm_application_insights", {"local_authentication_enabled": false, "tags": tags("dev")}),
		res("azurerm_container_registry", {"admin_enabled": false, "anonymous_pull_enabled": false, "tags": tags("dev")}),
		res("azurerm_kubernetes_cluster", aks("dev", "Free")),
		res("azurerm_role_assignment", {"role_definition_name": "AcrPull"}),
		res("azurerm_subnet", {"name": "snet-aks"}),
	]))
}

# ─── Identity: zero keys ──────────────────────────────────────────────────
test_foundry_local_auth_denied if {
	denied_with(plan([res("azurerm_cognitive_account", object.union(foundry, {"local_auth_enabled": true}))]), "local_auth_enabled must be false")
}

test_foundry_local_auth_missing_denied if {
	denied_with(plan([res("azurerm_cognitive_account", object.remove(foundry, ["local_auth_enabled"]))]), "local_auth_enabled must be false")
}

test_log_analytics_local_auth_denied if {
	denied_with(plan([res("azurerm_log_analytics_workspace", {"local_authentication_enabled": true, "tags": tags("dev")})]), "local_authentication_enabled")
}

test_app_insights_local_auth_denied if {
	denied_with(plan([res("azurerm_application_insights", {"local_authentication_enabled": true, "tags": tags("dev")})]), "local_authentication_enabled")
}

test_acr_admin_denied if {
	denied_with(plan([res("azurerm_container_registry", {"admin_enabled": true, "tags": tags("dev")})]), "admin_enabled")
}

test_acr_anonymous_pull_denied if {
	denied_with(plan([res("azurerm_container_registry", {"admin_enabled": false, "anonymous_pull_enabled": true, "tags": tags("dev")})]), "anonymous_pull_enabled")
}

# ─── Network: private only ────────────────────────────────────────────────
test_foundry_public_access_denied if {
	denied_with(plan([res("azurerm_cognitive_account", object.union(foundry, {"public_network_access_enabled": true}))]), "public_network_access_enabled")
}

test_key_vault_public_access_denied if {
	denied_with(plan([res("azurerm_key_vault", {"public_network_access_enabled": true, "tags": tags("dev")})]), "public_network_access_enabled")
}

test_foundry_unrestricted_outbound_denied if {
	denied_with(plan([res("azurerm_cognitive_account", object.union(foundry, {"outbound_network_access_restricted": false}))]), "outbound_network_access_restricted")
}

# ─── AKS ──────────────────────────────────────────────────────────────────
test_aks_public_cluster_denied if {
	denied_with(plan([res("azurerm_kubernetes_cluster", object.union(aks("dev", "Free"), {"private_cluster_enabled": false}))]), "private_cluster_enabled")
}

test_aks_local_accounts_denied if {
	denied_with(plan([res("azurerm_kubernetes_cluster", object.union(aks("dev", "Free"), {"local_account_disabled": false}))]), "local_account_disabled")
}

test_dev_aks_free_tier_allowed if {
	clean(plan([res("azurerm_kubernetes_cluster", aks("dev", "Free"))]))
}

test_prod_aks_standard_tier_allowed if {
	clean(plan([res("azurerm_kubernetes_cluster", aks("prod", "Standard"))]))
}

test_prod_aks_free_tier_denied if {
	denied_with(plan([res("azurerm_kubernetes_cluster", aks("prod", "Free"))]), "prod AKS must use sku_tier")
}

# ─── RBAC ─────────────────────────────────────────────────────────────────
test_owner_by_name_denied if {
	denied_with(plan([res("azurerm_role_assignment", {"role_definition_name": "Owner"})]), "\"Owner\"")
}

test_uaa_by_name_denied if {
	denied_with(plan([res("azurerm_role_assignment", {"role_definition_name": "User Access Administrator"})]), "User Access Administrator")
}

test_owner_by_id_denied if {
	id := "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/8E3AF657-A8FF-443C-A75C-2FE8C4BCB635"
	denied_with(plan([res("azurerm_role_assignment", {"role_definition_id": id})]), "(by ID)")
}

test_deleting_owner_assignment_is_fine if {
	r := object.union(res("azurerm_role_assignment", {}), {"change": {"actions": ["delete"], "after": null}})
	clean(plan([r]))
}

# ─── Tags ─────────────────────────────────────────────────────────────────
test_missing_tags_denied if {
	denied_with(plan([res("azurerm_key_vault", {"public_network_access_enabled": false, "tags": {"project": "aifz"}})]), "missing required tags")
}

test_null_tags_denied if {
	denied_with(plan([res("azurerm_key_vault", {"public_network_access_enabled": false, "tags": null})]), "missing required tags")
}

test_unknown_environment_denied if {
	denied_with(plan([res("azurerm_key_vault", {"public_network_access_enabled": false, "tags": tags("staging")})]), "must be \"dev\" or \"prod\"")
}

test_untaggable_resource_skipped if {
	clean(plan([res("azurerm_monitor_diagnostic_setting", {"name": "diag"})]))
}

test_data_sources_ignored if {
	r := object.union(res("azurerm_resource_group", {"tags": null}), {"mode": "data"})
	clean(plan([r]))
}
