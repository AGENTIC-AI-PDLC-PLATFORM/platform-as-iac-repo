# C9. Providers locked and module sources pinned to a tag or commit: 0 unpinned.
#
# Every module call that leaves the root's own directory is pinned: a git source with
# ?ref=<release tag or full commit SHA>, or a registry module with an exact version. Shared modules
# are therefore always used by release, so a change to modules/ reaches a zone only when that
# zone's code moves to the new tag (and that zone's code owners approve). A local path may only go
# down (./...); inside a pinned module, its own relative calls are pinned with it. Provider locking
# is checked by CI (terraform init -lockfile=readonly).
package iac.c9

import data.iac.lib

release_tag := `^[a-z0-9-]+-v[0-9]+\.[0-9]+\.[0-9]+$`

commit_sha := `^[0-9a-f]{40}$`

local_source(source) if startswith(source, "./")

local_source(source) if startswith(source, "../")

git_source(source) if startswith(source, "git::")

git_source(source) if startswith(source, "github.com/")

registry_source(source) if regex.match(`^([a-z0-9.-]+/)?[a-z0-9_-]+/[a-z0-9_-]+/[a-z0-9_-]+$`, source)

ref(source) := r if {
	some part in split(split(source, "?")[1], "&")
	startswith(part, "ref=")
	r := substring(part, 4, -1)
}

pinned_ref(source) if regex.match(release_tag, ref(source))

pinned_ref(source) if regex.match(commit_sha, ref(source))

# true when an enclosing module call is remote, so this call is resolved inside a pinned module
inside_remote_module(path) if {
	count(path) > 2
	some i in numbers.range(0, count(path) - 3)
	path[i] == "module_calls"
	ancestor := object.get(input.configuration.root_module, array.slice(path, 0, i + 2), {})
	not local_source(object.get(ancestor, "source", "./"))
}

deny contains msg if {
	some c in lib.module_calls
	local_source(c.call.source)
	contains(c.call.source, "..")
	not inside_remote_module(c.path)
	msg := sprintf("C9: module %s uses %s, outside this root; reference it by release tag (git::...//modules/<name>?ref=<name>-vX.Y.Z)", [concat(".", c.path), c.call.source])
}

deny contains msg if {
	some c in lib.module_calls
	git_source(c.call.source)
	not pinned_ref(c.call.source)
	msg := sprintf("C9: module %s is not pinned to a release tag or commit SHA: %s", [concat(".", c.path), c.call.source])
}

deny contains msg if {
	some c in lib.module_calls
	registry_source(c.call.source)
	not regex.match(`^=?\s*[0-9]+\.[0-9]+\.[0-9]+$`, object.get(c.call, "version_constraint", ""))
	msg := sprintf("C9: registry module %s (%s) needs an exact version, not %q", [concat(".", c.path), c.call.source, object.get(c.call, "version_constraint", "")])
}

deny contains msg if {
	some c in lib.module_calls
	not local_source(c.call.source)
	not git_source(c.call.source)
	not registry_source(c.call.source)
	msg := sprintf("C9: module %s comes from %s; use a pinned git or registry source", [concat(".", c.path), c.call.source])
}
