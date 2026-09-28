# ─── Shared helpers for every Terraform plan rule ─────────────────────────
# Input: `terraform show -json tfplan` (the PLAN, not the code). Evaluating
# the plan means module inputs, variables and defaults are already resolved:
# we judge what WILL exist in Azure, not what the .tf files happen to say.
package terraform

import rego.v1

# Every managed resource that will exist after apply (creates, updates,
# replacements and unchanged resources). Pure deletes are ignored.
resources contains r if {
	some r in input.resource_changes
	r.mode == "managed"
	not r.change.actions == ["delete"]
}

after(r) := r.change.after

# Tags as an object, even when the plan has `tags = null`.
tags_of(r) := t if {
	t := after(r).tags
	is_object(t)
}

tags_of(r) := {} if not is_object(after(r).tags)
