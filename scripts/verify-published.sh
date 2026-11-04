#!/usr/bin/env bash
# verify-published.sh: after the control-plane apply, the services published to Build and Run in
# published/control-plane.tfvars.json must be exactly the control plane's outputs.
set -euo pipefail
cd "$(dirname "$0")/.."
actual=$(terraform -chdir=zones/control-plane output -json control_plane_services | jq -S .)
published=$(jq -S .control_plane_services published/control-plane.tfvars.json)
if [[ $actual != "$published" ]]; then
  echo "::error::published/control-plane.tfvars.json does not match the control plane's outputs; update it in a pull request"
  diff <(echo "$published") <(echo "$actual") || true
  exit 1
fi
echo "published/control-plane.tfvars.json matches the control plane's outputs"
