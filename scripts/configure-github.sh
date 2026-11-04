#!/usr/bin/env bash
# configure-github.sh: the GitHub side of platform-as-iac-repo, run once by an organization owner (and
# again after any change: it updates what exists). Needs gh authenticated as an owner.
#   - one runner group per zone, open to platform-as-iac-repo only (prints the IDs for bootstrap's tfvars)
#   - environments control-plane, build, run: deployments from main only; run needs a second
#     approver (Squad B lead or CoE security engineer, never the person who started the run)
#   - ruleset on main: pull request, code-owner review, approval of the last push, checks-complete
#   - ruleset on release tags (*-v*): only the platform lead and the squad leads create them
# Usage: ORG=<org> [REPO=platform-as-iac-repo] bash scripts/configure-github.sh
set -euo pipefail
: "${ORG:?set ORG to your organization slug}"
REPO=${REPO:-platform-as-iac-repo}

team_id() { gh api "orgs/$ORG/teams/$1" --jq .id; }
repo_id=$(gh api "repos/$ORG/$REPO" --jq .id)

echo "== runner groups"
declare -A group_ids
for zone in control-plane build run; do
  name="platform-as-iac-repo-$zone"
  id=$(gh api --paginate "orgs/$ORG/actions/runner-groups" --jq ".runner_groups[] | select(.name == \"$name\") | .id")
  body=$(jq -n --arg name "$name" --argjson repo "$repo_id" \
    '{name: $name, visibility: "selected", selected_repository_ids: [$repo], allows_public_repositories: false}')
  if [[ -z $id ]]; then
    id=$(gh api -X POST "orgs/$ORG/actions/runner-groups" --input - --jq .id <<< "$body")
    echo "created  $name ($id)"
  else
    gh api -X PATCH "orgs/$ORG/actions/runner-groups/$id" --input - --silent \
      <<< "$(jq 'del(.selected_repository_ids)' <<< "$body")"
    gh api -X PUT "orgs/$ORG/actions/runner-groups/$id/repositories" --input - --silent \
      <<< "$(jq -n --argjson repo "$repo_id" '{selected_repository_ids: [$repo]}')"
    echo "updated  $name ($id)"
  fi
  group_ids[$zone]=$id
done

echo "== environments"
squad_b_lead=$(team_id coe-squad-b-lead)
security=$(team_id coe-security)
for env in control-plane build run; do
  if [[ $env == run ]]; then
    body=$(jq -n --argjson a "$squad_b_lead" --argjson b "$security" '{
      wait_timer: 0, prevent_self_review: true,
      reviewers: [{type: "Team", id: $a}, {type: "Team", id: $b}],
      deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}}')
  else
    body='{"wait_timer": 0, "reviewers": [], "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}'
  fi
  gh api -X PUT "repos/$ORG/$REPO/environments/$env" --input - --silent <<< "$body"
  if ! gh api "repos/$ORG/$REPO/environments/$env/deployment-branch-policies" \
    --jq '.branch_policies[].name' | grep -qx main; then
    gh api -X POST "repos/$ORG/$REPO/environments/$env/deployment-branch-policies" \
      -f name=main -f type=branch --silent
  fi
  echo "environment $env: deployments from main only$([[ $env == run ]] && echo ', second approver required')"
done

echo "== rulesets"
upsert_ruleset() {  # upsert_ruleset <name> <json>
  local id
  id=$(gh api "repos/$ORG/$REPO/rulesets" --jq ".[] | select(.name == \"$1\") | .id")
  if [[ -z $id ]]; then
    gh api -X POST "repos/$ORG/$REPO/rulesets" --input - --silent <<< "$2"
    echo "created  ruleset $1"
  else
    gh api -X PUT "repos/$ORG/$REPO/rulesets/$id" --input - --silent <<< "$2"
    echo "updated  ruleset $1"
  fi
}

upsert_ruleset main "$(jq -n '{
  name: "main", target: "branch", enforcement: "active", bypass_actors: [],
  conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
  rules: [
    {type: "deletion"},
    {type: "non_fast_forward"},
    {type: "pull_request", parameters: {
      required_approving_review_count: 1, require_code_owner_review: true,
      dismiss_stale_reviews_on_push: true, require_last_push_approval: true,
      required_review_thread_resolution: false}},
    {type: "required_status_checks", parameters: {
      strict_required_status_checks_policy: true,
      required_status_checks: [{context: "checks-complete"}]}}
  ]}')"

release_bypass=$(for team in coe-platform-lead coe-squad-a-lead coe-squad-b-lead; do
  jq -n --argjson id "$(team_id "$team")" '{actor_id: $id, actor_type: "Team", bypass_mode: "always"}'
done | jq -s .)
upsert_ruleset module-releases "$(jq -n --argjson bypass "$release_bypass" '{
  name: "module-releases", target: "tag", enforcement: "active", bypass_actors: $bypass,
  conditions: {ref_name: {include: ["refs/tags/*-v*"], exclude: []}},
  rules: [{type: "creation"}, {type: "update"}, {type: "deletion"}]}')"

echo
echo "bootstrap/terraform.tfvars:"
echo "  runner_group_ids = { control-plane = ${group_ids[control-plane]}, build = ${group_ids[build]}, run = ${group_ids[run]} }"
