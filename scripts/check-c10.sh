#!/usr/bin/env bash
# check-c10.sh (C10): Build and Run use the same modules/data-plane, Run at most one release behind.
# Run after scripts/validate-all.sh, in a clone with tags.
set -euo pipefail
cd "$(dirname "$0")/.."
input=$(mktemp)
trap 'rm -f "$input"' EXIT
scripts/c10-input.sh > "$input"
jq -r '"Build: \(.build)\nRun:   \(.run)\nReleases: \(.releases | join(", "))"' "$input"
denials=$(opa eval --format raw --data policy --ignore fixtures --input "$input" \
  'concat("\n", sort([m | some m in data.iac.c10.deny]))')
if [[ -n $denials ]]; then
  while IFS= read -r line; do echo "::error::$line"; done <<< "$denials"
  exit 1
fi
echo "C10 ok"
