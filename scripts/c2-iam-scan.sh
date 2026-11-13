#!/usr/bin/env bash
# c2-iam-scan.sh <zone> (C2): lists the IAM policies of the zone's project (Cloud Asset Inventory,
# with the zone's plan identity) and reports any grant to another platform project's service
# account or to a federated identity. Run in every zone, this finds any zone identity holding a
# permission in another zone's project. Opens or updates the issue "IAM: <zone>", label iam-scan.
set -euo pipefail
zone=$1
cd "$(dirname "$0")/.."
source scripts/lib.sh
project=$(tfvar "$zone" project_id)
others=()
for other in "${ZONES[@]}"; do
  [[ $other != "$zone" ]] && others+=("$(tfvar "$other" project_id)")
done

pattern="^serviceAccount:[^@]+@($(IFS='|'; echo "${others[*]}"))\\.iam\\.gserviceaccount\\.com\$|^principal(Set)?://"
findings=$(gcloud asset search-all-iam-policies --scope="projects/$project" --format=json \
  | jq -r --arg p "$pattern" '.[] | .resource as $resource | (.policy.bindings // [])[] | .role as $role
      | .members[] | select(test($p)) | "| `\($resource)` | `\($role)` | `\(.)` |"')

report="C2 IAM analysis of $project ($zone) on $(date -u +%F)"
if [[ -z $findings ]]; then
  echo "$report: no grant to another zone's identity"
  track_issue "IAM: $zone" iam-scan close
  exit 0
fi
table=$'| Resource | Role | Member |\n|---|---|---|\n'"$findings"
echo "$table" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
track_issue "IAM: $zone" iam-scan open "$report found grants to identities outside the zone (C2):

$table"
echo "::error::C2: identities outside the $zone zone hold permissions in $project"
exit 1
