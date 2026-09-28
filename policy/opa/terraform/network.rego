# ─── No public PaaS endpoints: private endpoints only ─────────────────────
package terraform

import rego.v1

# Services reached only through Private Endpoints + Private DNS.
# (ACR is intentionally absent: its firewall is deny-by-default with a
#  just-in-time IP rule for image pushes - see ADR-0006.)
private_only_types := {"azurerm_cognitive_account", "azurerm_key_vault"}

deny contains msg if {
	some r in resources
	r.type in private_only_types
	not after(r).public_network_access_enabled == false
	msg := sprintf("%s: public_network_access_enabled must be false (reach it through its Private Endpoint)", [r.address])
}

# Foundry may only call out to destinations we allow (data exfiltration guard).
deny contains msg if {
	some r in resources
	r.type == "azurerm_cognitive_account"
	not after(r).outbound_network_access_restricted == true
	msg := sprintf("%s: outbound_network_access_restricted must be true", [r.address])
}
