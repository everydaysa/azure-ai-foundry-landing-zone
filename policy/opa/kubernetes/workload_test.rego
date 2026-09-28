# Unit tests for the Kubernetes rules:  opa test policy/opa -v
package kubernetes_test

import rego.v1

import data.kubernetes

digest := "example.azurecr.io/app@sha256:1111111111111111111111111111111111111111111111111111111111111111"

good_container := {
	"name": "app",
	"image": digest,
	"securityContext": {
		"allowPrivilegeEscalation": false,
		"readOnlyRootFilesystem": true,
		"capabilities": {"drop": ["ALL"]},
	},
}

deployment(c) := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": "app"},
	"spec": {"template": {"spec": {
		"securityContext": {"runAsNonRoot": true, "runAsUser": 10001},
		"containers": [c],
	}}},
}

with_sc(patch) := object.union(good_container, {"securityContext": patch})

denied_with(inp, text) if {
	msgs := kubernetes.deny with input as inp
	some m in msgs
	contains(m, text)
}

clean(inp) if {
	msgs := kubernetes.deny with input as inp
	count(msgs) == 0
}

# ─── Compliant ────────────────────────────────────────────────────────────
test_hardened_deployment_passes if {
	clean(deployment(good_container))
}

test_array_and_list_inputs_supported if {
	clean([deployment(good_container)])
	clean({"kind": "List", "items": [deployment(good_container)]})
	denied_with([deployment(object.union(good_container, {"image": "nginx:1.27"}))], "pinned by digest")
}

test_job_and_cronjob_checked if {
	job := {"kind": "Job", "metadata": {"name": "j"}, "spec": {"template": {"spec": {"containers": [good_container]}}}}
	denied_with(job, "runAsNonRoot")
	cron := {"kind": "CronJob", "metadata": {"name": "c"}, "spec": {"jobTemplate": {"spec": {"template": {"spec": {"containers": [object.union(good_container, {"image": "busybox:latest"})]}}}}}}
	denied_with(cron, "pinned by digest")
}

# ─── Images ───────────────────────────────────────────────────────────────
test_tag_only_image_denied if {
	denied_with(deployment(object.union(good_container, {"image": "curlimages/curl:8.11.1"})), "pinned by digest")
}

test_init_container_checked if {
	d := deployment(good_container)
	bad := object.union(d, {"spec": {"template": {"spec": {"initContainers": [object.union(good_container, {"name": "init", "image": "alpine:3"})]}}}})
	denied_with(bad, "\"init\"")
}

# ─── Non-root ─────────────────────────────────────────────────────────────
test_missing_run_as_non_root_denied if {
	d := object.union(deployment(good_container), {"spec": {"template": {"spec": {"securityContext": {"runAsNonRoot": false}}}}})
	denied_with(d, "runAsNonRoot")
}

test_container_level_run_as_non_root_accepted if {
	c := with_sc({"runAsNonRoot": true})
	job := {"kind": "Job", "metadata": {"name": "j"}, "spec": {"template": {"spec": {"containers": [c]}}}}
	clean(job)
}

test_container_overrides_pod_to_root_denied if {
	denied_with(deployment(with_sc({"runAsNonRoot": false})), "runAsNonRoot")
}

test_uid_zero_denied if {
	denied_with(deployment(with_sc({"runAsUser": 0})), "UID 0")
}

# ─── Container hardening ──────────────────────────────────────────────────
test_writable_root_fs_denied if {
	denied_with(deployment(with_sc({"readOnlyRootFilesystem": false})), "readOnlyRootFilesystem")
}

test_privilege_escalation_denied if {
	denied_with(deployment(with_sc({"allowPrivilegeEscalation": true})), "allowPrivilegeEscalation")
}

test_privileged_denied if {
	denied_with(deployment(with_sc({"privileged": true})), "must not be privileged")
}

test_capabilities_not_dropped_denied if {
	denied_with(deployment(with_sc({"capabilities": {"drop": ["NET_RAW"]}})), "drop ALL")
}

test_host_network_denied if {
	d := object.union(deployment(good_container), {"spec": {"template": {"spec": {"hostNetwork": true}}}})
	denied_with(d, "hostNetwork")
}

# ─── Namespace + Service ──────────────────────────────────────────────────
test_restricted_namespace_passes if {
	clean({"kind": "Namespace", "metadata": {"name": "ai-app", "labels": {"pod-security.kubernetes.io/enforce": "restricted"}}})
}

test_baseline_namespace_denied if {
	denied_with({"kind": "Namespace", "metadata": {"name": "x", "labels": {"pod-security.kubernetes.io/enforce": "baseline"}}}, "restricted")
}

test_clusterip_service_passes if {
	clean({"kind": "Service", "metadata": {"name": "app"}, "spec": {"type": "ClusterIP"}})
}

test_load_balancer_service_denied if {
	denied_with({"kind": "Service", "metadata": {"name": "app"}, "spec": {"type": "LoadBalancer"}}, "LoadBalancer")
}

test_non_workload_objects_ignored if {
	clean({"kind": "ConfigMap", "metadata": {"name": "cfg"}, "data": {"a": "b"}})
}
