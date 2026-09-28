# ─── Least privilege: Terraform never hands out "keys to the kingdom" ─────
package terraform

import rego.v1

# Roles that can grant access or change anything: never assigned by this code.
# Built-in role IDs are fixed across every Azure tenant.
privileged_roles := {
	"Owner": "8e3af657-a8ff-443c-a75c-2fe8c4bcb635", # gitleaks:allow - public built-in role ID, identical in every tenant
	"User Access Administrator": "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9", # gitleaks:allow - public built-in role ID, identical in every tenant
	"Role Based Access Control Administrator": "f58310d9-a9f6-439a-9e8d-f62e7b41a168", # gitleaks:allow - public built-in role ID, identical in every tenant
}

deny contains msg if {
	some r in resources
	r.type == "azurerm_role_assignment"
	some name, _ in privileged_roles
	after(r).role_definition_name == name
	msg := sprintf("%s: assigning privileged role %q is not allowed", [r.address, name])
}

# Same check when the role is referenced by ID instead of name.
deny contains msg if {
	some r in resources
	r.type == "azurerm_role_assignment"
	id := lower(after(r).role_definition_id)
	some name, guid in privileged_roles
	endswith(id, guid)
	msg := sprintf("%s: assigning privileged role %q (by ID) is not allowed", [r.address, name])
}
