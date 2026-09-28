# ─── Zero keys: every data plane is Entra ID only ─────────────────────────
package terraform

import rego.v1

# AI Foundry: API keys must not authenticate (ADR-0001, ADR-0005).
deny contains msg if {
	some r in resources
	r.type == "azurerm_cognitive_account"
	not after(r).local_auth_enabled == false
	msg := sprintf("%s: local_auth_enabled must be false (API keys must not authenticate; Entra ID only)", [r.address])
}

# Log Analytics + App Insights: no shared-key / instrumentation-key ingestion
# (ADR-0004). Checkov has no check for these - this is the gap OPA closes.
deny contains msg if {
	some r in resources
	r.type in {"azurerm_log_analytics_workspace", "azurerm_application_insights"}
	not after(r).local_authentication_enabled == false
	msg := sprintf("%s: local_authentication_enabled must be false (Entra-only telemetry ingestion)", [r.address])
}

# Container registry: no shared admin password, no anonymous pulls (ADR-0006).
deny contains msg if {
	some r in resources
	r.type == "azurerm_container_registry"
	not after(r).admin_enabled == false
	msg := sprintf("%s: admin_enabled must be false (identity-only registry access)", [r.address])
}

deny contains msg if {
	some r in resources
	r.type == "azurerm_container_registry"
	after(r).anonymous_pull_enabled == true
	msg := sprintf("%s: anonymous_pull_enabled must be false", [r.address])
}
