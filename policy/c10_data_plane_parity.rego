# C10. Build and Run use the same modules/data-plane, Run at most 1 release behind Build.
#
# Input (scripts/c10-input.sh, from the module resolution of zones/build and zones/run):
#   {"build": "<source of module data_plane>", "run": "<source>",
#    "releases": ["data-plane-v0.1.0", ...]}   release tags, oldest first
package iac.c10

parse(source) := {"module": m[1], "ref": m[2]} if {
	m := regex.find_all_string_submatch_n(`^(.*//modules/data-plane)\?ref=(data-plane-v[0-9]+\.[0-9]+\.[0-9]+)$`, source, 1)[0]
}

position(ref) := i if {
	some i, tag in input.releases
	tag == ref
}

deny contains msg if {
	some zone in ["build", "run"]
	not parse(input[zone])
	msg := sprintf("C10: %s does not use modules/data-plane by release tag: %q", [zone, input[zone]])
}

deny contains msg if {
	parse(input.build).module != parse(input.run).module
	msg := sprintf("C10: Build and Run use different data-plane modules: %s and %s", [parse(input.build).module, parse(input.run).module])
}

deny contains msg if {
	some zone in ["build", "run"]
	ref := parse(input[zone]).ref
	not position(ref)
	msg := sprintf("C10: %s uses %s, which is not a data-plane release tag", [zone, ref])
}

deny contains msg if {
	position(parse(input.run).ref) > position(parse(input.build).ref)
	msg := sprintf("C10: Run (%s) is ahead of Build (%s); a change lands in Build first", [parse(input.run).ref, parse(input.build).ref])
}

deny contains msg if {
	behind := position(parse(input.build).ref) - position(parse(input.run).ref)
	behind > 1
	msg := sprintf("C10: Run (%s) is %d releases behind Build (%s); at most 1", [parse(input.run).ref, behind, parse(input.build).ref])
}
