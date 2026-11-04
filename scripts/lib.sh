# shellcheck shell=bash
# Helpers sourced by the other scripts. Run from the repository root.

# shellcheck disable=SC2034 # used by the scripts that source this file
ZONES=(control-plane build run)

die() {
  echo "::error::$*" >&2
  exit 1
}

# tfvar <zone> <name>: a string value from zones/<zone>/terraform.tfvars
tfvar() {
  local value
  value=$(sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "zones/$1/terraform.tfvars" | head -n 1)
  [[ -n $value ]] || die "no $2 in zones/$1/terraform.tfvars"
  printf '%s\n' "$value"
}

# backend <zone> <bucket|prefix>: a value from zones/<zone>/backend.hcl
backend() {
  local value
  value=$(sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "zones/$1/backend.hcl" | head -n 1)
  [[ -n $value ]] || die "no $2 in zones/$1/backend.hcl"
  printf '%s\n' "$value"
}

# subnet <zone> <name>: a subnet range from zones/<zone>/terraform.tfvars
subnet() {
  local value
  value=$(sed -n "/^subnets[[:space:]]*=/,/^}/ s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "zones/$1/terraform.tfvars" | head -n 1)
  [[ -n $value ]] || die "no subnet $2 in zones/$1/terraform.tfvars"
  printf '%s\n' "$value"
}

# github_api <method> <path> [json body]: call the GitHub REST API with GH_TOKEN
github_api() {
  local method=$1 path=$2 body=${3:-}
  local args=(-sS --fail-with-body -X "$method"
    -H "Authorization: Bearer ${GH_TOKEN:?GH_TOKEN is not set}"
    -H 'Accept: application/vnd.github+json'
    -H 'X-GitHub-Api-Version: 2022-11-28')
  [[ -n $body ]] && args+=(-H 'Content-Type: application/json' --data "$body")
  curl "${args[@]}" "${GITHUB_API_URL:-https://api.github.com}/$path"
}

# track_issue <title> <label> <open|close> [body]: keep one open issue per title (C2, C12 reports)
track_issue() {
  local title=$1 label=$2 action=$3 body=${4:-} number
  number=$(github_api GET "repos/$GITHUB_REPOSITORY/issues?state=open&labels=$label&per_page=100" \
    | jq -r --arg t "$title" 'map(select(.title == $t))[0].number // empty')
  if [[ $action == open ]]; then
    if [[ -n $number ]]; then
      github_api POST "repos/$GITHUB_REPOSITORY/issues/$number/comments" "$(jq -n --arg b "$body" '{body: $b}')" > /dev/null
    else
      github_api POST "repos/$GITHUB_REPOSITORY/issues" \
        "$(jq -n --arg t "$title" --arg b "$body" --arg l "$label" '{title: $t, body: $b, labels: [$l]}')" > /dev/null
    fi
  elif [[ -n $number ]]; then
    github_api POST "repos/$GITHUB_REPOSITORY/issues/$number/comments" \
      "$(jq -n --arg b "${body:-Resolved: the last scheduled run found nothing.}" '{body: $b}')" > /dev/null
    github_api PATCH "repos/$GITHUB_REPOSITORY/issues/$number" '{"state": "closed"}' > /dev/null
  fi
}
