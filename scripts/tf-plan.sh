#!/usr/bin/env bash
# tf-plan.sh <zone> <plan|apply|drift>: init and plan one zone root, leaving plan.bin, plan.json
# and plan.txt in zones/<zone>/.
#   plan   read-only identity, no state lock; a zone whose state does not exist yet (before its
#          first apply) is planned against an empty local state.
#   apply  apply identity, state locked; the apply step then applies plan.bin.
#   drift  like plan, exit status 2 when the zone has drifted (C12).
set -euo pipefail
zone=$1 mode=$2
cd "$(dirname "$0")/.."
source scripts/lib.sh
cd "zones/$zone"

bucket=$(cd ../.. && backend "$zone" bucket)
prefix=$(cd ../.. && backend "$zone" prefix)
state_object=$(jq -rn --arg o "$prefix/default.tfstate" '$o | @uri')
init=(terraform init -input=false -lockfile=readonly)

if [[ $mode == apply ]]; then
  "${init[@]}" -backend-config=backend.hcl
else
  code=$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${GOOGLE_OAUTH_ACCESS_TOKEN:?run scripts/gcp-token.sh plan first}" \
    "https://storage.googleapis.com/storage/v1/b/$bucket/o/$state_object")
  case $code in
    200) "${init[@]}" -backend-config=backend.hcl ;;
    404)
      echo "No state yet in gs://$bucket/$prefix: planning against an empty state."
      printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
      "${init[@]}" ;;
    *) die "cannot check gs://$bucket/$prefix/default.tfstate (HTTP $code)" ;;
  esac
fi

args=(-input=false -out=plan.bin)
[[ $mode == apply ]] || args+=(-lock=false)
[[ $zone == build || $zone == run ]] && args+=(-var-file=../../published/control-plane.tfvars.json)

status=0
if [[ $mode == drift ]]; then
  terraform plan "${args[@]}" -detailed-exitcode || status=$?
  [[ $status == 0 || $status == 2 ]] || exit "$status"
else
  terraform plan "${args[@]}"
fi
terraform show -json plan.bin > plan.json
terraform show -no-color plan.bin > plan.txt
exit "$status"
