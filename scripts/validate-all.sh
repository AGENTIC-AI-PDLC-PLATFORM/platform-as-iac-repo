#!/usr/bin/env bash
# validate-all.sh: terraform init (no backend) and validate for every root and module.
# Roots must have a committed .terraform.lock.hcl that already covers their providers (C9:
# -lockfile=readonly fails otherwise; create it with scripts/lock-providers.sh).
# Zone roots download the shared modules at the release tags they pin, so the git credential for
# this repository must be configured (the workflow does it with the job token).
set -euo pipefail
cd "$(dirname "$0")/.."

roots=(bootstrap zones/control-plane zones/build zones/run)
modules=(modules/account-baseline modules/network modules/data-plane bootstrap/zone)

failed=0
for dir in "${roots[@]}" "${modules[@]}"; do
  lock=()
  if [[ " ${roots[*]} " == *" $dir "* ]]; then
    [[ -f $dir/.terraform.lock.hcl ]] || { echo "::error file=$dir::no .terraform.lock.hcl (C9): run scripts/lock-providers.sh"; failed=1; continue; }
    lock=(-lockfile=readonly)
  fi
  if terraform -chdir="$dir" init -backend=false -input=false "${lock[@]}" > /dev/null \
    && terraform -chdir="$dir" validate -no-color; then
    echo "$dir: valid"
  else
    echo "::error file=$dir::terraform init or validate failed"
    failed=1
  fi
done
exit "$failed"
