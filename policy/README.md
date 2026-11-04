# policy/

Plan checks of the ADR's Confirmation table, in Rego (OPA 1.x). They belong to this repository,
not to the policy-source repository (ADR-007).

| File | Control | Input | Runs on |
|---|---|---|---|
| `c1_run_trust.rego` | C1 | plan JSON | bootstrap, every zone |
| `c3_no_build_run_path.rego` | C3 | plan JSON | bootstrap, every zone |
| `c4_no_cross_zone_state.rego` | C4 | plan JSON | bootstrap, every zone |
| `c5_egress_via_proxy.rego` | C5 | plan JSON | bootstrap, Build, Run |
| `c6_state_isolation.rego` | C6 | plan JSON | bootstrap |
| `c9_pinned_sources.rego` | C9 | plan JSON | bootstrap, every zone |
| `c10_data_plane_parity.rego` | C10 | module sources of Build and Run + release tags (`scripts/c10-input.sh`) | every pull request |

Each check defines `deny` (a set of messages) in package `iac.<id>`; `lib.rego` holds the helpers.
`data.context.zone` tells a check which root it is looking at.

```bash
terraform show -json plan.bin > plan.json
scripts/check-plan.sh build plan.json       # the checks that apply to that root
opa test policy -v                           # C11: every check, on passing and failing fixtures
```

`fixtures/` holds compact copies of real plans of this repository (`*_pass`, which every check
must accept) and one modified plan per violation (which its check must deny). Unknown values make
a check deny, not pass: run the bootstrap checks on a plan made after the first apply.
