#!/usr/bin/env bash
# check-no-static-credentials.sh (C7): no service-account key in the code, no credentials file in
# a provider or backend, no cloud credential passed to a workflow as a secret. (The organisation
# policies of account-baseline also forbid creating or uploading keys; gitleaks scans the diff.)
set -euo pipefail
cd "$(dirname "$0")/.."
found=0
report() { echo "::error file=$1::C7: $2"; found=1; }

while IFS=: read -r file line _; do
  report "$file,line=$line" "service-account key resource"
done < <(grep -RnE 'resource[[:space:]]+"google_service_account_key"' --include='*.tf' --exclude-dir=.terraform . || true)

while IFS=: read -r file line _; do
  report "$file,line=$line" "credentials set in Terraform; credentials come from the zone's token broker"
done < <(grep -RnE '^[[:space:]]*credentials[[:space:]]*=' --include='*.tf' --include='*.hcl' --exclude-dir=.terraform . || true)

while IFS=: read -r file line _; do
  report "$file,line=$line" "cloud credential passed as a secret; jobs get credentials from the zone's token broker"
done < <(grep -RnE 'secrets\.[A-Z0-9_]*(GOOGLE|GCP|GCLOUD|SERVICE_ACCOUNT|CREDENTIALS)|credentials_json' .github/ || true)

[[ $found == 0 ]] && echo "C7: no static cloud credential found"
exit "$found"
