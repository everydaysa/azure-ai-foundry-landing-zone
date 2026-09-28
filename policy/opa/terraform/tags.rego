# ─── Ownership: every taggable resource says what it is and who owns it ───
package terraform

import rego.v1

required_tags := {"project", "environment", "managed_by"}

# "Taggable" = the resource type has a `tags` attribute in the plan.
# Subnets, role assignments, diagnostic settings etc. have none and are skipped.
deny contains msg if {
	some r in resources
	"tags" in object.keys(after(r))
	present := {k | some k, v in tags_of(r); v != ""}
	missing := required_tags - present
	count(missing) > 0
	msg := sprintf("%s: missing required tags %v", [r.address, sort(missing)])
}

# The environment tag must be one we know (it drives the prod-only rules).
deny contains msg if {
	some r in resources
	env := tags_of(r).environment
	not env in {"dev", "prod"}
	msg := sprintf("%s: tag environment=%q must be \"dev\" or \"prod\"", [r.address, env])
}
