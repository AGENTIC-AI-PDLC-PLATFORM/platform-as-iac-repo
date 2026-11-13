#!/usr/bin/env bash
# c1-negative-test.sh (C1 proof): run on a Build runner. Every attempt to obtain or use a Run
# credential from here must be refused; the script fails if any attempt succeeds.
# Runs on every pull request touching bootstrap/, and on demand for design review #1 (Day 22).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source scripts/lib.sh
[[ ${PLATFORM_AS_IAC_REPO_ZONE:-} == build ]] || die "run this on a Build runner (PLATFORM_AS_IAC_REPO_ZONE=${PLATFORM_AS_IAC_REPO_ZONE:-unset})"
run_project=$(tfvar run project_id)
run_bucket=$(backend run bucket)
run_host=$(python3 -c 'import ipaddress, sys; print(list(ipaddress.ip_network(sys.argv[1]).hosts())[1])' "$(subnet run workloads)")

passed=0 failed=0
refused() {  # refused <what> <command...>: the command must fail
  local what=$1
  shift
  if "$@" > /dev/null 2>&1; then
    echo "::error::C1 broken: $what succeeded from a Build runner"
    failed=$((failed + 1))
  else
    echo "refused as required: $what"
    passed=$((passed + 1))
  fi
}

# This job's own credentials: Build's plan identity (a previous step ran scripts/gcp-token.sh plan).
: "${GOOGLE_OAUTH_ACCESS_TOKEN:?run scripts/gcp-token.sh plan in a previous step}"

refused "the job reaches the runner VM's identity (metadata server)" \
  curl -sf -m 5 -H 'Metadata-Flavor: Google' \
  http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token
refused "the Build broker hands apply credentials to a pull-request job" \
  env GCP_TOKEN_PROBE=1 scripts/gcp-token.sh apply
for account in plan apply runner; do
  refused "Build's plan identity impersonates platform-as-iac-repo-$account@$run_project" \
    gcloud auth print-access-token --impersonate-service-account="platform-as-iac-repo-$account@$run_project.iam.gserviceaccount.com"
done
refused "Build's plan identity lists the Run state bucket" \
  curl -sf -m 20 -H "Authorization: Bearer $GOOGLE_OAUTH_ACCESS_TOKEN" \
  "https://storage.googleapis.com/storage/v1/b/$run_bucket/o?maxResults=1"
refused "a TCP connection from Build to the Run workloads range ($run_host:443)" \
  timeout 5 bash -c "exec 3<>/dev/tcp/$run_host/443"

echo "C1: $passed attempts refused, $failed succeeded"
[[ $failed == 0 ]]
