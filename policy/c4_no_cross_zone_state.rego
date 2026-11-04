# C4. No zone reads another zone's state: 0 terraform_remote_state or backend data sources across
# zones. Zones share only the reviewed, non-secret files in published/.
package iac.c4

import data.iac.lib

object_types := {
	"google_storage_bucket_object",
	"google_storage_bucket_object_content",
	"google_storage_bucket_objects",
}

deny contains msg if {
	some res in lib.config_resources
	res.mode == "data"
	res.type == "terraform_remote_state"
	msg := sprintf("C4: %s reads Terraform state; zones share only what is in published/", [res.address])
}

# Reading objects of a state bucket (named <project>-tfstate) is reading state, whatever the
# data source.
deny contains msg if {
	some res in lib.config_resources
	res.mode == "data"
	res.type in object_types
	endswith(res.expressions.bucket.constant_value, "-tfstate")
	msg := sprintf("C4: %s reads the state bucket %s", [res.address, res.expressions.bucket.constant_value])
}

deny contains msg if {
	some r in lib.deferred_data
	r.type in object_types
	endswith(object.get(r.change.after, "bucket", ""), "-tfstate")
	msg := sprintf("C4: %s reads the state bucket %s", [r.address, r.change.after.bucket])
}

deny contains msg if {
	walk(input.prior_state, [_, node])
	node.mode == "data"
	node.type in object_types
	endswith(object.get(node.values, "bucket", ""), "-tfstate")
	msg := sprintf("C4: %s reads the state bucket %s", [node.address, node.values.bucket])
}
