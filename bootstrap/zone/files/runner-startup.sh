#!/bin/bash
# Startup script of a platform-as-iac-repo runner VM. Runs as root on the first boot of a fresh VM:
#   1. installs pinned tools through the company DLP reverse proxy (the only egress);
#   2. creates the runner user and blocks the metadata server for it, so jobs cannot use this
#      VM's identity;
#   3. starts the token broker, the only way a job gets this zone's plan or apply credentials;
#   4. registers a just-in-time runner for one job, runs it, then stops the VM. The managed
#      instance group recreates the VM from its template, so every job starts on a fresh VM.
# Configuration comes from the instance metadata written by bootstrap/zone/runners.tf.
set -euo pipefail

log() { logger -t platform-as-iac-repo-runner -- "$*"; echo "platform-as-iac-repo-runner: $*"; }
stop_vm() { log "stopping the VM: $1"; sync; shutdown -h now; exit 0; }
trap 'stop_vm "startup failed at line $LINENO"' ERR

metadata() {
  curl -sSf -H 'Metadata-Flavor: Google' \
    "http://169.254.169.254/computeMetadata/v1/instance/attributes/$1"
}
cfg() {  # cfg <dotted.key>: one value from the runner configuration
  python3 -c 'import json, sys
value = json.load(open("/etc/platform-as-iac-repo/config.json"))
for key in sys.argv[1].split("."):
    value = value[key]
print(json.dumps(value) if isinstance(value, (list, dict)) else value)' "$1"
}

install -d -m 0700 /etc/platform-as-iac-repo
metadata platform-as-iac-repo-config > /etc/platform-as-iac-repo/config.json
metadata platform-as-iac-repo-broker > /usr/local/sbin/platform-as-iac-repo-broker
chmod 0600 /etc/platform-as-iac-repo/config.json
chmod 0700 /usr/local/sbin/platform-as-iac-repo-broker

ZONE=$(cfg zone)
PROJECT=$(cfg project_id)
PROXY="http://$(cfg proxy.address):$(cfg proxy.port)"
NO_PROXY_LIST="169.254.169.254,metadata.google.internal,.googleapis.com,.pkg.dev,localhost,127.0.0.1"
export https_proxy=$PROXY HTTPS_PROXY=$PROXY http_proxy=$PROXY HTTP_PROXY=$PROXY
export no_proxy=$NO_PROXY_LIST NO_PROXY=$NO_PROXY_LIST
log "zone $ZONE, project $PROJECT, egress through $PROXY"

# 1. Packages and pinned tools ---------------------------------------------------------------------
printf 'Acquire::http::Proxy "%s";\nAcquire::https::Proxy "%s";\n' "$PROXY" "$PROXY" \
  > /etc/apt/apt.conf.d/90platform-as-iac-repo-proxy
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  ca-certificates curl git iptables jq openssl python3-cryptography python3-jwt unzip
command -v gcloud > /dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y -qq google-cloud-cli

verify() {  # verify <file> <sha256>
  echo "$2  $1" | sha256sum --check --quiet -
}
work=$(mktemp -d)

tf_version=$(cfg tools.terraform_version)
tf_sha=$(cfg tools.terraform_sha256)
tf_base="https://releases.hashicorp.com/terraform/$tf_version"
curl -fsSL --retry 5 -o "$work/terraform.zip" "$tf_base/terraform_${tf_version}_linux_amd64.zip"
if [ -z "$tf_sha" ]; then
  curl -fsSL --retry 5 -o "$work/terraform.sums" "$tf_base/terraform_${tf_version}_SHA256SUMS"
  tf_sha=$(awk '/_linux_amd64\.zip$/ { print $1 }' "$work/terraform.sums")
fi
verify "$work/terraform.zip" "$tf_sha"
unzip -oq "$work/terraform.zip" terraform -d /usr/local/bin

opa_version=$(cfg tools.opa_version)
curl -fsSL --retry 5 -o "$work/opa" \
  "https://github.com/open-policy-agent/opa/releases/download/v$opa_version/opa_linux_amd64_static"
verify "$work/opa" "$(cfg tools.opa_sha256)"
install -m 0755 "$work/opa" /usr/local/bin/opa

runner_version=$(cfg tools.runner_version)
curl -fsSL --retry 5 -o "$work/runner.tar.gz" \
  "https://github.com/actions/runner/releases/download/v$runner_version/actions-runner-linux-x64-$runner_version.tar.gz"
verify "$work/runner.tar.gz" "$(cfg tools.runner_sha256)"
install -d /opt/actions-runner
tar -xzf "$work/runner.tar.gz" -C /opt/actions-runner
/opt/actions-runner/bin/installdependencies.sh > /dev/null
rm -rf "$work"

# 2. Runner user: no sudo, no docker, no metadata server (DNS on the same address stays open) ------
useradd --create-home --shell /bin/bash runner
iptables -I OUTPUT -m owner --uid-owner runner -d 169.254.169.254 -p tcp ! --dport 53 -j REJECT
iptables -I FORWARD -d 169.254.169.254 -j REJECT
ip6tables -I OUTPUT -m owner --uid-owner runner -d fd20:ce::254 -j REJECT 2>/dev/null || true
if runuser -u runner -- curl -sf -m 5 -H 'Metadata-Flavor: Google' \
  http://169.254.169.254/computeMetadata/v1/instance/id > /dev/null; then
  stop_vm "the runner user can still reach the metadata server"
fi

# 3. Token broker ----------------------------------------------------------------------------------
cfg broker > /etc/platform-as-iac-repo/broker.json
chmod 0600 /etc/platform-as-iac-repo/broker.json
cat > /etc/systemd/system/platform-as-iac-repo-broker.service <<EOF
[Unit]
Description=platform-as-iac-repo token broker (zone $ZONE)
After=network-online.target

[Service]
Environment=BROKER_CONFIG=/etc/platform-as-iac-repo/broker.json
Environment=https_proxy=$PROXY
Environment=no_proxy=$NO_PROXY_LIST
ExecStart=/usr/bin/python3 /usr/local/sbin/platform-as-iac-repo-broker
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now platform-as-iac-repo-broker.service

# 4. One just-in-time runner, for one job ------------------------------------------------------------
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
app_key() {
  local token
  token=$(curl -sSf -H 'Metadata-Flavor: Google' \
    http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token | jq -r .access_token)
  curl -sSf -H "Authorization: Bearer $token" \
    "https://secretmanager.googleapis.com/v1/projects/$PROJECT/secrets/github-runner-app-key/versions/latest:access" \
    | jq -r .payload.data | base64 -d
}

key=""
for _ in $(seq 1 20); do
  key=$(app_key 2>/dev/null) && [ -n "$key" ] && break
  log "no GitHub App key in Secret Manager yet; retrying in 30 s"
  sleep 30
done
[ -n "$key" ] || stop_vm "no GitHub App key in Secret Manager"

now=$(date +%s)
header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$(cfg github.app_id)" | b64url)
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign <(printf '%s\n' "$key") | b64url)
unset key

install_token=$(curl -sSf -X POST \
  -H "Authorization: Bearer $header.$payload.$signature" -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/app/installations/$(cfg github.installation_id)/access_tokens" | jq -r .token)

runner_name="$(hostname)-$(date +%s)"
jit=$(jq -n --arg name "$runner_name" --argjson group "$(cfg github.runner_group_id)" \
  --argjson labels "$(cfg github.labels)" \
  '{name: $name, runner_group_id: $group, labels: $labels, work_folder: "_work"}' \
  | curl -sSf -X POST -H "Authorization: Bearer $install_token" -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/orgs/$(cfg github.organization)/actions/runners/generate-jitconfig" --data @- \
  | jq -r .encoded_jit_config)
unset install_token

cat > /opt/actions-runner/.env <<EOF
https_proxy=$PROXY
HTTPS_PROXY=$PROXY
http_proxy=$PROXY
HTTP_PROXY=$PROXY
no_proxy=$NO_PROXY_LIST
NO_PROXY=$NO_PROXY_LIST
PLATFORM_AS_IAC_REPO_ZONE=$ZONE
PLATFORM_AS_IAC_REPO_BROKER=http://127.0.0.1:8099
EOF
chown -R runner:runner /opt/actions-runner

trap - ERR
log "runner $runner_name registered in zone $ZONE; waiting for one job"
runuser -u runner -- /opt/actions-runner/run.sh --jitconfig "$jit" || log "runner exited with status $?"
stop_vm "job finished"
