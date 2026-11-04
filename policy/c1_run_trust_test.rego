package iac.c1_test

import data.iac.c1

denies(plan, zone) := result if {
	result := c1.deny with input as plan with data.context as {"zone": zone}
}

test_real_plans_pass if {
	count(denies(data.fixtures.bootstrap_pass, "bootstrap")) == 0
	count(denies(data.fixtures.control_plane_pass, "control-plane")) == 0
	count(denies(data.fixtures.build_pass, "build")) == 0
	count(denies(data.fixtures.run_pass, "run")) == 0
}

test_build_runner_minting_run_apply_tokens_fails if {
	some msg in denies(data.fixtures.c1_build_runner_mints_run_apply, "bootstrap")
	contains(msg, "platform-as-iac-repo-runner@example-pdlc-build")
}

test_zone_changing_who_acts_as_pipeline_identity_fails if {
	some msg in denies(data.fixtures.c1_zone_changes_pipeline_identity, "run")
	contains(msg, "only bootstrap/ may")
}

test_project_wide_impersonation_fails if {
	some msg in denies(data.fixtures.c1_project_wide_impersonation, "build")
	contains(msg, "roles/iam.serviceAccountTokenCreator")
}

test_bootstrap_plan_checked_as_a_zone_fails if {
	count(denies(data.fixtures.bootstrap_pass, "build")) > 0
}
