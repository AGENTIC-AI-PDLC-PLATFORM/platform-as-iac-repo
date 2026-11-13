#!/usr/bin/env bash
# c10-input.sh: prints the input of policy/c10_data_plane_parity.rego: the data-plane module
# source of zones/build and zones/run, as resolved by terraform init, and the data-plane release
# tags oldest first. Run after scripts/validate-all.sh (which runs init) in a full clone.
set -euo pipefail
cd "$(dirname "$0")/.."
source=()
for zone in build run; do
  modules=zones/$zone/.terraform/modules/modules.json
  [[ -f $modules ]] || { echo "no $modules: run terraform init in zones/$zone first" >&2; exit 1; }
  source+=("$(jq -r '.Modules[] | select(.Key == "data_plane") | .Source' "$modules")")
done
git tag --list 'data-plane-v*' --sort=v:refname \
  | jq -R . | jq -s --arg build "${source[0]}" --arg run "${source[1]}" '{build: $build, run: $run, releases: .}'
