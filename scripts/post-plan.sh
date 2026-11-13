#!/usr/bin/env bash
# post-plan.sh <zone>: posts zones/<zone>/plan.txt to the pull request as one comment per zone,
# updated on each push. Terraform already hides values marked sensitive; anything that still looks
# like a credential is masked before posting, and the plan is cut to fit a comment.
set -euo pipefail
zone=$1
cd "$(dirname "$0")/.."
source scripts/lib.sh
: "${PR_NUMBER:?}" "${GITHUB_REPOSITORY:?}"

marker="<!-- platform-as-iac-repo-plan:$zone -->"
plan=$(sed -E \
  -e 's/ya29\.[A-Za-z0-9._-]+/<redacted access token>/g' \
  -e 's/(gh[opsu]_|github_pat_)[A-Za-z0-9_]{20,}/<redacted GitHub token>/g' \
  -e 's/AIza[0-9A-Za-z_-]{35}/<redacted API key>/g' \
  -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----.*/<redacted private key>/' \
  "zones/$zone/plan.txt" | sed -n '/^Terraform will perform/,$p')
[[ -n $plan ]] || plan="No changes."
if (( ${#plan} > 60000 )); then
  plan="${plan:0:60000}"$'\n\n… cut: the full plan is in the job log.'
fi

body="$marker
### Plan: \`$zone\`
Run [#$GITHUB_RUN_ID]($GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID), commit \`${GITHUB_SHA:0:7}\`

<details><summary>terraform plan</summary>

\`\`\`
$plan
\`\`\`
</details>"

existing=$(github_api GET "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments?per_page=100" \
  | jq -r --arg m "$marker" 'map(select(.body | startswith($m)))[0].id // empty')
payload=$(jq -n --arg b "$body" '{body: $b}')
if [[ -n $existing ]]; then
  github_api PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$existing" "$payload" > /dev/null
else
  github_api POST "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" "$payload" > /dev/null
fi
echo "plan of $zone posted to #$PR_NUMBER"
