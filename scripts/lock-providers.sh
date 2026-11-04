#!/usr/bin/env bash
# lock-providers.sh: writes .terraform.lock.hcl in every root with the provider checksums of the
# platforms that run Terraform here (runners: linux_amd64; people: macOS and Windows), then commit
# the files (C9). Run it once before the first pull request, and again whenever a provider version
# constraint changes. Needs git access to this repository (the zones pin its modules by tag).
set -euo pipefail
cd "$(dirname "$0")/.."
platforms=(-platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64 -platform=windows_amd64)
for root in bootstrap zones/control-plane zones/build zones/run; do
  terraform -chdir="$root" init -backend=false -input=false > /dev/null
  terraform -chdir="$root" providers lock "${platforms[@]}"
  echo "$root/.terraform.lock.hcl written"
done
