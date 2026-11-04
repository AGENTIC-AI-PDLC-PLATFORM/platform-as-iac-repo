# Helpers shared by the checks. Input: `terraform show -json` of a saved plan.
# data.context.zone names the root being checked: bootstrap, control-plane, build or run.
package iac.lib

# Managed resources that exist after the apply: created, updated, replaced or unchanged.
resources contains r if {
	some r in input.resource_changes
	r.mode == "managed"
	r.change.actions != ["delete"]
}

# Data sources that are read during the apply (those read during the plan are in prior_state).
deferred_data contains r if {
	some r in input.resource_changes
	r.mode == "data"
}

of_type(types) := {r | some r in resources; r.type in types}

# true when the attribute is only known after the apply
unknown(r, attr) if r.change.after_unknown[attr] == true

# value of a root-module input variable
variable(name) := input.variables[name].value

# "" when no context is given: every zone-plan rule then applies, no bootstrap allowance does.
default zone := ""

zone := data.context.zone

# Every resource block of the configuration, at any module depth.
config_resources contains res if {
	walk(input.configuration, [path, value])
	count(path) > 0
	path[count(path) - 1] == "resources"
	some res in value
}

# Every module call of the configuration: its path from root_module and its block.
module_calls contains {"path": path, "call": call} if {
	walk(input.configuration.root_module, [path, call])
	count(path) >= 2
	path[count(path) - 2] == "module_calls"
}
