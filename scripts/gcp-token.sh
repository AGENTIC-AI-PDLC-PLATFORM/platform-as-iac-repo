#!/usr/bin/env bash
# gcp-token.sh <plan|apply>: asks this runner's token broker for the zone's plan or apply
# credentials (C1) and exports them to the next steps:
#   GOOGLE_OAUTH_ACCESS_TOKEN        Terraform's google provider and gcs backend
#   CLOUDSDK_AUTH_ACCESS_TOKEN_FILE  gcloud
# The job needs `permissions: id-token: write`. Tokens last one hour (C7).
# GCP_TOKEN_PROBE=1: only report whether the broker grants the role (C1 negative test).
set -euo pipefail
role=${1:?usage: gcp-token.sh plan|apply}
: "${PLATFORM_AS_IAC_REPO_BROKER:?not on a platform-as-iac-repo runner (PLATFORM_AS_IAC_REPO_BROKER is not set)}"
: "${ACTIONS_ID_TOKEN_REQUEST_URL:?the job needs permissions: id-token: write}"

oidc=$(curl -sS --fail-with-body -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=platform-as-iac-repo-broker" | jq -r .value)

response=$(jq -n --arg role "$role" --arg token "$oidc" '{role: $role, token: $token}' \
  | curl -sS -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' --data @- \
    "$PLATFORM_AS_IAC_REPO_BROKER/token")
code=${response##*$'\n'}
body=${response%$'\n'*}

if [[ ${GCP_TOKEN_PROBE:-0} == 1 ]]; then
  [[ $code == 200 ]]
  exit
fi
[[ $code == 200 ]] || { echo "::error::token broker refused $role ($code): $(jq -r .error <<< "$body")"; exit 1; }

token=$(jq -r .access_token <<< "$body")
echo "::add-mask::$token"
umask 077
printf '%s' "$token" > "$RUNNER_TEMP/gcp-access-token"
{
  echo "GOOGLE_OAUTH_ACCESS_TOKEN=$token"
  echo "CLOUDSDK_AUTH_ACCESS_TOKEN_FILE=$RUNNER_TEMP/gcp-access-token"
} >> "$GITHUB_ENV"
echo "$role credentials of zone $PLATFORM_AS_IAC_REPO_ZONE: $(jq -r .service_account <<< "$body"), until $(jq -r .expire_time <<< "$body")"
