#!/usr/bin/env bash
# check-plan.sh <root> <plan.json>: runs the policy/ checks that apply to this root against its
# plan (`terraform show -json`). <root>: bootstrap, control-plane, build or run. Exit 1 on any denial.
#   bootstrap      C1 C3 C4 C5 C6 C9   (run by the two named people on the bootstrap plan)
#   control-plane  C1 C3 C4 C9
#   build, run     C1 C3 C4 C5 C9
set -euo pipefail
root=$1 plan=$2
repo=$(cd "$(dirname "$0")/.." && pwd)
case $root in
  bootstrap) checks=(c1 c3 c4 c5 c6 c9) ;;
  control-plane) checks=(c1 c3 c4 c9) ;;
  build | run) checks=(c1 c3 c4 c5 c9) ;;
  *) echo "unknown root: $root" >&2; exit 2 ;;
esac

context=$(mktemp)
trap 'rm -f "$context"' EXIT
printf '{"context": {"zone": "%s"}}' "$root" > "$context"

failed=0
for check in "${checks[@]}"; do
  denials=$(opa eval --format raw --data "$repo/policy" --ignore fixtures --data "$context" --input "$plan" \
    "concat(\"\\n\", sort([m | some m in data.iac.$check.deny]))")
  if [[ -z $denials ]]; then
    echo "${check^^} ok"
  else
    failed=1
    while IFS= read -r line; do echo "::error::$line"; done <<< "$denials"
  fi
done
exit "$failed"
