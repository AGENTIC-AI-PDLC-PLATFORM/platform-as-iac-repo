# published/

Control-plane outputs that Build and Run need, published as non-secret parameters (ADR: "no zone
reads another zone's state"). `zones/build` and `zones/run` read `control-plane.tfvars.json` with
`-var-file`; their `control_plane_services` variable has no default, so a plan without this file
fails instead of removing the endpoints.

- Change it in the same pull request that publishes or removes a control-plane service.
- The control-plane apply compares it with `terraform output control_plane_services` and fails on
  any difference, so Build and Run never apply against stale values.
- Code owner: Squad A lead (CODEOWNERS).
