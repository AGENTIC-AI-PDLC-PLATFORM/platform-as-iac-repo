# C6. One state backend per account, with its own key, versioning and an EU region:
# 3 backends, 0 readers from another zone. Runs on the bootstrap plan, where the backends live.
package iac.c6

import data.iac.lib

state_buckets := {r |
	some r in lib.of_type({"google_storage_bucket"})
	object.get(r.change.after, "labels", {}).purpose == "terraform-state"
}

state_bucket_names := {r.change.after.name | some r in state_buckets}

deny contains msg if {
	lib.zone == "bootstrap"
	count(state_buckets) != 3
	msg := sprintf("C6: %d state buckets (labelled purpose=terraform-state); expected 3, one per zone project", [count(state_buckets)])
}

deny contains msg if {
	some project in {r.change.after.project | some r in state_buckets}
	n := count({r | some r in state_buckets; r.change.after.project == project})
	n > 1
	msg := sprintf("C6: project %s has %d state buckets; expected one", [project, n])
}

deny contains msg if {
	some r in state_buckets
	not eu_location(upper(r.change.after.location))
	msg := sprintf("C6: %s is in %s, not an EU location", [r.address, r.change.after.location])
}

eu_location(location) if startswith(location, "EUROPE-")

eu_location(location) if location in {"EU", "EUR4", "EUR5", "EUR7", "EUR8"}

deny contains msg if {
	some r in state_buckets
	not r.change.after.versioning[0].enabled
	msg := sprintf("C6: %s has no object versioning, so a lost or corrupted state cannot be restored", [r.address])
}

deny contains msg if {
	some r in state_buckets
	not own_key(r)
	msg := sprintf("C6: %s is not encrypted with a key of its own project", [r.address])
}

own_key(r) if startswith(r.change.after.encryption[0].default_kms_key_name, sprintf("projects/%s/", [r.change.after.project]))

deny contains msg if {
	some r in state_buckets
	r.change.after.uniform_bucket_level_access != true
	msg := sprintf("C6: %s allows object ACLs; access must come from bucket IAM only", [r.address])
}

deny contains msg if {
	some r in state_buckets
	r.change.after.public_access_prevention != "enforced"
	msg := sprintf("C6: %s does not enforce public access prevention", [r.address])
}

# --- who may read a state bucket -------------------------------------------------------------------

project_of_bucket(name) := r.change.after.project if {
	some r in state_buckets
	r.change.after.name == name
}

deny contains msg if {
	some r in lib.of_type({"google_storage_bucket_iam_binding", "google_storage_bucket_iam_policy"})
	object.get(r.change.after, "bucket", "") in state_bucket_names
	msg := sprintf("C6: %s sets an authoritative policy on a state bucket; use google_storage_bucket_iam_member", [r.address])
}

deny contains msg if {
	some r in lib.of_type({"google_storage_bucket_iam_member"})
	project := project_of_bucket(r.change.after.bucket)
	not allowed_reader(project, r.change.after.member)
	msg := sprintf("C6: %s lets %s into the state bucket %s; only that project's plan and apply identities and break-glass may", [r.address, r.change.after.member, r.change.after.bucket])
}

allowed_reader(project, member) if {
	some role in ["plan", "apply"]
	member == sprintf("serviceAccount:platform-as-iac-repo-%s@%s.iam.gserviceaccount.com", [role, project])
}

allowed_reader(_, member) if member == lib.variable("break_glass_group")

deny contains msg if {
	some r in lib.of_type({"google_storage_bucket_iam_member"})
	r.change.after.bucket in state_bucket_names
	some attr in ["bucket", "member"]
	lib.unknown(r, attr)
	msg := sprintf("C6: %s: %s is only known after apply; re-run on a plan made after the apply", [r.address, attr])
}

# The control-plane bucket also keeps bootstrap's state: the pipeline identities may only read
# objects under zones/control-plane/.
object_reader_roles := {
	"roles/storage.objectViewer",
	"roles/storage.objectUser",
	"roles/storage.objectAdmin",
	"roles/storage.admin",
}

deny contains msg if {
	control_plane := lib.variable("projects")["control-plane"].project_id
	some r in lib.of_type({"google_storage_bucket_iam_member"})
	project_of_bucket(r.change.after.bucket) == control_plane
	startswith(r.change.after.member, "serviceAccount:")
	r.change.after.role in object_reader_roles
	not limited_to_control_plane_prefix(r)
	msg := sprintf("C6: %s lets %s read every object of %s, including bootstrap's state; limit it to zones/control-plane/", [r.address, r.change.after.member, r.change.after.bucket])
}

limited_to_control_plane_prefix(r) if {
	some condition in r.change.after.condition
	contains(condition.expression, "/objects/zones/control-plane/")
}
