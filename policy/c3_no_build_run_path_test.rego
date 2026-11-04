package iac.c3_test

import data.iac.c3

denies(plan, zone) := result if {
	result := c3.deny with input as plan with data.context as {"zone": zone}
}

test_real_plans_pass if {
	count(denies(data.fixtures.bootstrap_pass, "bootstrap")) == 0
	count(denies(data.fixtures.control_plane_pass, "control-plane")) == 0
	count(denies(data.fixtures.build_pass, "build")) == 0
	count(denies(data.fixtures.run_pass, "run")) == 0
}

test_peering_fails if {
	some msg in denies(data.fixtures.c3_build_run_peering, "build")
	contains(msg, "google_compute_network_peering")
}

test_endpoint_to_a_run_service_fails if {
	some msg in denies(data.fixtures.c3_endpoint_to_run_service, "build")
	contains(msg, "example-pdlc-run")
}

test_run_publishing_a_service_fails if {
	some msg in denies(data.fixtures.c3_run_publishes_service, "run")
	contains(msg, "only the control plane may")
}
