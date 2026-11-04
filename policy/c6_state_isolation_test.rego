package iac.c6_test

import data.iac.c6

denies(plan) := result if {
	result := c6.deny with input as plan with data.context as {"zone": "bootstrap"}
}

test_bootstrap_plan_passes if {
	count(denies(data.fixtures.bootstrap_pass)) == 0
}

test_state_outside_the_eu_fails if {
	some msg in denies(data.fixtures.c6_state_outside_eu)
	contains(msg, "not an EU location")
}

test_build_reading_run_state_fails if {
	some msg in denies(data.fixtures.c6_build_reads_run_state)
	contains(msg, "platform-as-iac-repo-plan@example-pdlc-build")
}

test_bootstrap_state_readable_by_control_plane_identity_fails if {
	some msg in denies(data.fixtures.c6_bootstrap_state_readable)
	contains(msg, "bootstrap's state")
}
