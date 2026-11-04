# C1. The Run plan and apply roles trust only Run-zone runners: 0 assumable from Build.
#
# On GCP each zone's plan and apply identities are service accounts (platform-as-iac-repo-plan, -apply).
# Only the runner account of the same project (platform-as-iac-repo-runner, attached only to that zone's
# runner VMs) may mint their tokens. This check runs on the bootstrap plan, where those grants
# live, and on every zone plan, where none of them may be touched. Unknown values are denied:
# re-run the check on a plan made after the apply.
package iac.c1

import data.iac.lib

impersonation_roles := {
	"roles/iam.serviceAccountTokenCreator",
	"roles/iam.serviceAccountUser",
	"roles/iam.serviceAccountOpenIdTokenCreator",
	"roles/iam.workloadIdentityUser",
	"roles/iam.serviceAccountKeyAdmin",
	"roles/iam.serviceAccountAdmin",
	"roles/editor",
	"roles/owner",
}

sa_iam_types := {
	"google_service_account_iam_member",
	"google_service_account_iam_binding",
	"google_service_account_iam_policy",
}

# {"role": plan|apply|runner, "project": ...} of a platform-as-iac-repo service account id
pipeline_account(id) := {"role": m[1], "project": m[2]} if {
	m := regex.find_all_string_submatch_n(
		`^projects/[^/]+/serviceAccounts/platform-as-iac-repo-(plan|apply|runner)@([a-z0-9-]+)\.iam\.gserviceaccount\.com$`,
		id, 1,
	)[0]
}

runner_of(project) := sprintf("serviceAccount:platform-as-iac-repo-runner@%s.iam.gserviceaccount.com", [project])

# --- who may act as a pipeline identity -------------------------------------------------------------

deny contains msg if {
	some r in lib.of_type(sa_iam_types)
	lib.zone != "bootstrap"
	account := pipeline_account(r.change.after.service_account_id)
	msg := sprintf("C1: %s changes who may act as platform-as-iac-repo-%s in %s; only bootstrap/ may", [r.address, account.role, account.project])
}

deny contains msg if {
	some r in lib.of_type({"google_service_account_iam_binding", "google_service_account_iam_policy"})
	lib.zone == "bootstrap"
	pipeline_account(r.change.after.service_account_id)
	msg := sprintf("C1: %s sets an authoritative policy on a pipeline identity; use google_service_account_iam_member", [r.address])
}

deny contains msg if {
	some r in lib.of_type({"google_service_account_iam_member"})
	lib.zone == "bootstrap"
	account := pipeline_account(r.change.after.service_account_id)
	not allowed_grant(account, r.change.after.role, r.change.after.member)
	msg := sprintf("C1: %s lets %s use %s on platform-as-iac-repo-%s in %s; only that project's runner may mint plan and apply tokens", [r.address, r.change.after.member, r.change.after.role, account.role, account.project])
}

allowed_grant(account, role, member) if {
	account.role in {"plan", "apply"}
	role == "roles/iam.serviceAccountTokenCreator"
	member == runner_of(account.project)
}

deny contains msg if {
	some r in lib.of_type(sa_iam_types)
	some attr in ["service_account_id", "member", "members", "role", "policy_data"]
	lib.unknown(r, attr)
	msg := sprintf("C1: %s: %s is only known after apply, so who may act as a pipeline identity cannot be checked; re-run on a plan made after the apply", [r.address, attr])
}

# --- project-wide grants also reach the pipeline identities -----------------------------------------

deny contains msg if {
	some r in lib.of_type({"google_project_iam_member"})
	r.change.after.role in impersonation_roles
	not allowed_project_grant(r.change.after.project, r.change.after.member)
	msg := sprintf("C1: %s grants %s on project %s to %s, which would let it act as the project's pipeline identities", [r.address, r.change.after.role, r.change.after.project, r.change.after.member])
}

# bootstrap only: the project's own apply identity, and break-glass
allowed_project_grant(project, member) if {
	lib.zone == "bootstrap"
	member == sprintf("serviceAccount:platform-as-iac-repo-apply@%s.iam.gserviceaccount.com", [project])
}

allowed_project_grant(_, member) if {
	lib.zone == "bootstrap"
	member == lib.variable("break_glass_group")
}

deny contains msg if {
	some r in lib.of_type({"google_project_iam_binding", "google_project_iam_policy"})
	msg := sprintf("C1: %s is authoritative and could remove the pipeline grants made by bootstrap/; use google_project_iam_member", [r.address])
}

deny contains msg if {
	some r in lib.of_type({"google_project_iam_member"})
	some attr in ["role", "member", "project"]
	lib.unknown(r, attr)
	r.change.after.role in impersonation_roles
	msg := sprintf("C1: %s: %s is only known after apply; re-run on a plan made after the apply", [r.address, attr])
}

# --- where the runner identity is attached --------------------------------------------------------

vm_types := {
	"google_compute_instance",
	"google_compute_instance_template",
	"google_compute_region_instance_template",
}

deny contains msg if {
	some r in lib.of_type(vm_types)
	some sa in r.change.after.service_account
	startswith(sa.email, "platform-as-iac-repo-")
	not runner_attached_in_own_project(r, sa.email)
	msg := sprintf("C1: %s attaches %s; only bootstrap/ may attach the runner identity, and only to its own project's runners", [r.address, sa.email])
}

runner_attached_in_own_project(r, email) if {
	lib.zone == "bootstrap"
	email == sprintf("platform-as-iac-repo-runner@%s.iam.gserviceaccount.com", [r.change.after.project])
}

# --- no federation into a zone ---------------------------------------------------------------------

deny contains msg if {
	some r in lib.of_type({"google_iam_workload_identity_pool", "google_iam_workload_identity_pool_provider"})
	msg := sprintf("C1: %s federates outside identities into the project; zone credentials come only from the zone's runners", [r.address])
}
