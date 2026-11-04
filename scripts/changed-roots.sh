#!/usr/bin/env bash
# changed-roots.sh <plan|apply> <base-sha> <head-sha>
# Prints, for $GITHUB_OUTPUT, which roots a change affects:
#   zones=["control-plane","build","run"]   (JSON, in apply order)
#   control-plane=true|false  build=...  run=...  bootstrap=true|false
# plan:  zones/<zone>/** plans that zone; published/** plans control plane, Build and Run;
#        policy/**, scripts/** and .github/** re-plan every zone against the new checks.
# apply: only zones/<zone>/** and published/** apply anything.
# modules/** affects no zone: zones use modules by release tag (C9).
set -euo pipefail
mode=$1 base=$2 head=$3
[[ $mode == plan || $mode == apply ]] || { echo "mode must be plan or apply" >&2; exit 2; }

if [[ $base =~ ^0+$ ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  files=$(git ls-files)   # first push or unknown base: everything
else
  files=$(git diff --name-only "$base" "$head")
fi

declare -A hit=([control-plane]=false [build]=false [run]=false)
bootstrap=false
while IFS= read -r f; do
  case $f in
    zones/control-plane/*) hit[control-plane]=true ;;
    zones/build/*) hit[build]=true ;;
    zones/run/*) hit[run]=true ;;
    published/*) hit[control-plane]=true; hit[build]=true; hit[run]=true ;;
    policy/* | scripts/* | .github/*)
      if [[ $mode == plan ]]; then hit[control-plane]=true; hit[build]=true; hit[run]=true; fi ;;
    bootstrap/*) bootstrap=true ;;
  esac
done <<< "$files"

zones=()
for zone in control-plane build run; do
  [[ ${hit[$zone]} == true ]] && zones+=("\"$zone\"")
  echo "$zone=${hit[$zone]}"
done
echo "zones=[$(IFS=,; echo "${zones[*]}")]"
echo "bootstrap=$bootstrap"
