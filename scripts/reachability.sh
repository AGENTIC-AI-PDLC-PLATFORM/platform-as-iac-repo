#!/usr/bin/env bash
# reachability.sh <zone> (C3, C5 proof after each network apply): Network Intelligence Center
# connectivity tests from the zone's workloads (control plane: services) subnet. Each must be
# unreachable: the internet, and for Build and Run the other zone's workloads range.
# Runs with the zone's apply credentials (roles/networkmanagement.admin in its own project).
set -euo pipefail
zone=$1
cd "$(dirname "$0")/.."
source scripts/lib.sh
project=$(tfvar "$zone" project_id)
source_subnet=workloads
[[ $zone == control-plane ]] && source_subnet=services
host() { python3 -c 'import ipaddress, sys; print(list(ipaddress.ip_network(sys.argv[1]).hosts())[1])' "$1"; }
source_ip=$(host "$(subnet "$zone" "$source_subnet")")

declare -A destinations=([internet]=8.8.8.8)
case $zone in
  build) destinations[run]=$(host "$(subnet run workloads)") ;;
  run) destinations[build]=$(host "$(subnet build workloads)") ;;
esac

failed=0
for name in "${!destinations[@]}"; do
  test_name="c3-$zone-to-$name"
  if gcloud network-management connectivity-tests describe "$test_name" --project="$project" > /dev/null 2>&1; then
    gcloud network-management connectivity-tests rerun "$test_name" --project="$project" > /dev/null
  else
    gcloud network-management connectivity-tests create "$test_name" --project="$project" \
      --source-ip-address="$source_ip" --source-network="projects/$project/global/networks/$zone" \
      --source-project="$project" --destination-ip-address="${destinations[$name]}" \
      --destination-port=443 --protocol=TCP > /dev/null
  fi
  result=$(gcloud network-management connectivity-tests describe "$test_name" --project="$project" \
    --format='value(reachabilityDetails.result)')
  if [[ $result == REACHABLE ]]; then
    echo "::error::C3/C5: $zone reaches $name (${destinations[$name]}:443)"
    failed=1
  else
    echo "$zone -> $name (${destinations[$name]}:443): $result"
  fi
done
exit "$failed"
