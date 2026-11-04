package iac.c4_test

import data.iac.c4

denies(plan, zone) := result if {
	result := c4.deny with input as plan with data.context as {"zone": zone}
}

test_real_plans_pass if {
	count(denies(data.fixtures.bootstrap_pass, "bootstrap")) == 0
	count(denies(data.fixtures.control_plane_pass, "control-plane")) == 0
	count(denies(data.fixtures.build_pass, "build")) == 0
	count(denies(data.fixtures.run_pass, "run")) == 0
}

test_remote_state_fails if {
	some msg in denies(data.fixtures.c4_run_reads_build_state, "run")
	contains(msg, "terraform_remote_state")
}

test_reading_a_state_bucket_fails if {
	some msg in denies(data.fixtures.c4_build_reads_run_state_bucket, "build")
	contains(msg, "example-pdlc-run-tfstate")
}
