package iac.c9_test

import data.iac.c9

denies(plan, zone) := result if {
	result := c9.deny with input as plan with data.context as {"zone": zone}
}

test_real_plans_pass if {
	count(denies(data.fixtures.bootstrap_pass, "bootstrap")) == 0
	count(denies(data.fixtures.control_plane_pass, "control-plane")) == 0
	count(denies(data.fixtures.build_pass, "build")) == 0
	count(denies(data.fixtures.run_pass, "run")) == 0
}

test_module_on_a_branch_fails if {
	some msg in denies(data.fixtures.c9_module_on_branch, "build")
	contains(msg, "?ref=main")
}

test_shared_module_by_local_path_fails if {
	some msg in denies(data.fixtures.c9_shared_module_by_path, "run")
	contains(msg, "../../modules/network")
}
