# ─── Kubernetes rules, evaluated on RENDERED manifests ────────────────────
# Input: one manifest, a JSON array of manifests, or a v1 List.
# scripts/opa-eval.sh splits `kubectl kustomize` output into single documents.
# These run BEFORE apply (shift left); Pod Security Admission "restricted"
# and Azure Policy (Gatekeeper) enforce the same ideas again in the cluster.
package kubernetes

import rego.v1

objects contains obj if {
	is_array(input)
	some obj in input
}

objects contains obj if {
	is_object(input)
	input.kind == "List"
	some obj in input.items
}

objects contains obj if {
	is_object(input)
	not input.kind == "List"
	obj := input
}

id(obj) := sprintf("%s/%s", [obj.kind, obj.metadata.name])

# Where the pod spec lives for each workload kind.
pod_template_kinds := {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"}

pod_spec(obj) := obj.spec.template.spec if obj.kind in pod_template_kinds

pod_spec(obj) := obj.spec.jobTemplate.spec.template.spec if obj.kind == "CronJob"

pod_spec(obj) := obj.spec if obj.kind == "Pod"

containers(spec) := array.concat(object.get(spec, "containers", []), object.get(spec, "initContainers", []))

# (object, pod spec, container) for every container in every workload.
workload_containers contains [obj, spec, c] if {
	some obj in objects
	spec := pod_spec(obj)
	some c in containers(spec)
}

# ─── Supply chain: immutable images ───────────────────────────────────────
deny contains msg if {
	some wc in workload_containers
	[obj, _, c] := wc
	not contains(c.image, "@sha256:")
	msg := sprintf("%s: container %q image %q must be pinned by digest (@sha256:...)", [id(obj), c.name, c.image])
}

# ─── Non-root (container setting wins over pod setting) ──────────────────
run_as_non_root(_, c) if c.securityContext.runAsNonRoot == true

run_as_non_root(spec, c) if {
	not c.securityContext.runAsNonRoot == false
	spec.securityContext.runAsNonRoot == true
}

deny contains msg if {
	some wc in workload_containers
	[obj, spec, c] := wc
	not run_as_non_root(spec, c)
	msg := sprintf("%s: container %q must set runAsNonRoot: true", [id(obj), c.name])
}

effective_uid(_, c) := c.securityContext.runAsUser

effective_uid(spec, c) := spec.securityContext.runAsUser if not has_container_uid(c)

has_container_uid(c) if is_number(c.securityContext.runAsUser)

deny contains msg if {
	some wc in workload_containers
	[obj, spec, c] := wc
	effective_uid(spec, c) == 0
	msg := sprintf("%s: container %q must not run as UID 0", [id(obj), c.name])
}

# ─── Immutable, unprivileged container ────────────────────────────────────
deny contains msg if {
	some wc in workload_containers
	[obj, _, c] := wc
	not c.securityContext.readOnlyRootFilesystem == true
	msg := sprintf("%s: container %q must set readOnlyRootFilesystem: true", [id(obj), c.name])
}

deny contains msg if {
	some wc in workload_containers
	[obj, _, c] := wc
	not c.securityContext.allowPrivilegeEscalation == false
	msg := sprintf("%s: container %q must set allowPrivilegeEscalation: false", [id(obj), c.name])
}

deny contains msg if {
	some wc in workload_containers
	[obj, _, c] := wc
	c.securityContext.privileged == true
	msg := sprintf("%s: container %q must not be privileged", [id(obj), c.name])
}

deny contains msg if {
	some wc in workload_containers
	[obj, _, c] := wc
	not "ALL" in object.get(c, ["securityContext", "capabilities", "drop"], [])
	msg := sprintf("%s: container %q must drop ALL capabilities", [id(obj), c.name])
}

# ─── No sharing the node's namespaces ─────────────────────────────────────
deny contains msg if {
	some obj in objects
	spec := pod_spec(obj)
	some field in ["hostNetwork", "hostPID", "hostIPC"]
	spec[field] == true
	msg := sprintf("%s: %s must not be true", [id(obj), field])
}

# ─── Namespaces must enforce Pod Security "restricted" ────────────────────
deny contains msg if {
	some obj in objects
	obj.kind == "Namespace"
	not obj.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"
	msg := sprintf("%s: label pod-security.kubernetes.io/enforce must be \"restricted\"", [id(obj)])
}

# ─── Private only: no Service may open a node port or a load balancer ─────
deny contains msg if {
	some obj in objects
	obj.kind == "Service"
	obj.spec.type in {"LoadBalancer", "NodePort"}
	msg := sprintf("%s: Service type %s is not allowed (ClusterIP only; no public entry points)", [id(obj), obj.spec.type])
}
