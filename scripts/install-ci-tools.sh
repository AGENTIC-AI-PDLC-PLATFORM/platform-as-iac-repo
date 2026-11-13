#!/usr/bin/env bash
# install-ci-tools.sh: installs the pinned static-check tools on a GitHub-hosted runner, each
# verified against its SHA-256, and puts them on the PATH of the following steps.
set -euo pipefail
bin=${RUNNER_TEMP:?}/bin
mkdir -p "$bin"
cd "$(mktemp -d)"

fetch() {  # fetch <url> <sha256> <file>
  curl -fsSL --retry 5 -o "$3" "$1"
  echo "$2  $3" | sha256sum --check --quiet -
}

fetch https://github.com/open-policy-agent/opa/releases/download/v1.22.0/opa_linux_amd64_static \
  791790254c598a942eb140959bcec9a47f844535a632fd01d11d870ba2a47047 opa
install -m 0755 opa "$bin/opa"

fetch https://github.com/terraform-linters/tflint/releases/download/v0.65.0/tflint_linux_amd64.zip \
  d4c545ed2e29d6338604b586f34f544f380f70f243aa72f7b484713835eaec61 tflint.zip
unzip -oq tflint.zip tflint -d "$bin"

fetch https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz \
  8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 actionlint.tar.gz
tar -xzf actionlint.tar.gz -C "$bin" actionlint

fetch https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz \
  551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb gitleaks.tar.gz
tar -xzf gitleaks.tar.gz -C "$bin" gitleaks

echo "$bin" >> "${GITHUB_PATH:-/dev/null}"
"$bin/opa" version | head -n 1
"$bin/tflint" --version | head -n 1
echo "actionlint $("$bin/actionlint" --version | head -n 1), gitleaks $("$bin/gitleaks" version)"
