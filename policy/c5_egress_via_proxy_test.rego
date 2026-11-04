package iac.c5_test

import data.iac.c5

denies(plan, zone) := result if {
	result := c5.deny with input as plan with data.context as {"zone": zone}
}

test_real_plans_pass if {
	count(denies(data.fixtures.bootstrap_pass, "bootstrap")) == 0
	count(denies(data.fixtures.build_pass, "build")) == 0
	count(denies(data.fixtures.run_pass, "run")) == 0
}

test_default_route_to_the_internet_fails if {
	some msg in denies(data.fixtures.c5_default_route_to_internet, "build")
	contains(msg, "default route")
}

test_keeping_gcp_default_route_fails if {
	some msg in denies(data.fixtures.c5_default_route_kept, "build")
	contains(msg, "delete_default_routes_on_create")
}

test_cloud_nat_fails if {
	some msg in denies(data.fixtures.c5_cloud_nat, "run")
	contains(msg, "Cloud NAT")
}
