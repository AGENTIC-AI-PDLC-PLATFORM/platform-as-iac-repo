package iac.c10_test

import data.iac.c10

denies(fixture) := result if {
	result := c10.deny with input as fixture
}

test_run_one_release_behind_passes if {
	count(denies(data.fixtures.c10_run_one_behind)) == 0
}

test_run_two_releases_behind_fails if {
	some msg in denies(data.fixtures.c10_run_two_behind)
	contains(msg, "2 releases behind")
}

test_run_ahead_of_build_fails if {
	some msg in denies(data.fixtures.c10_run_ahead)
	contains(msg, "ahead of Build")
}

test_unreleased_ref_fails if {
	some msg in denies(data.fixtures.c10_unreleased_ref)
	contains(msg, "build does not use modules/data-plane by release tag")
}
