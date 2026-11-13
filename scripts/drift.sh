#!/usr/bin/env bash
# drift.sh <zone> (C12): plans the zone read-only; on drift opens (or comments on) the issue
# "Drift: <zone>", labelled drift, and closes it once the zone is clean. The issue's age is the
# measure of "no drift left unresolved after 2 working days".
set -euo pipefail
zone=$1
cd "$(dirname "$0")/.."
source scripts/lib.sh

status=0
scripts/tf-plan.sh "$zone" drift || status=$?
title="Drift: $zone"
case $status in
  0)
    echo "$zone: no drift"
    track_issue "$title" drift close
    ;;
  2)
    summary=$(grep -E '^(Plan:|  # )' "zones/$zone/plan.txt" | head -n 50)
    track_issue "$title" drift open "Scheduled plan on $(date -u +%F) found drift in **$zone** (run [#$GITHUB_RUN_ID]($GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID)). Resolve within 2 working days (C12): bring the change into the code, or revert it by applying main.

\`\`\`
$summary
\`\`\`"
    echo "::warning::$zone has drifted"
    ;;
  *) exit "$status" ;;
esac
