#!/usr/bin/env bash
# chief-pr-provider-github.sh - GitHub adapter, backed by `gh`.
#
# pr_merge re-checks live, immediately before merging: open, non-draft,
# mergeable, no outstanding changes-requested review, and checks green. The
# exact current head is passed to `--match-head-commit` so a push landing
# between the read and the merge fails the merge instead of landing
# unverified commits.

pr_open() {
  local branch=$1 base=$2 title=$3 body=$4
  command -v gh >/dev/null 2>&1 || { echo "chief-pr-provider-github: gh is required" >&2; return 1; }
  gh pr create --head "$branch" --base "$base" --title "$title" --body "$body"
}

pr_state() {
  local url=$1
  command -v gh >/dev/null 2>&1 || { echo "chief-pr-provider-github: gh is required" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "chief-pr-provider-github: jq is required" >&2; return 1; }
  local json state draft mergeable decision
  json=$(gh pr view "$url" --json state,isDraft,mergeable,reviewDecision,statusCheckRollup) || return 1
  state=$(printf '%s' "$json" | jq -r '.state')
  [ "$state" = "OPEN" ] || { echo "state: $state"; return 0; }
  draft=$(printf '%s' "$json" | jq -r '.isDraft')
  mergeable=$(printf '%s' "$json" | jq -r '.mergeable')
  decision=$(printf '%s' "$json" | jq -r '.reviewDecision')
  [ "$draft" = "true" ] && echo "draft: still a draft PR"
  [ "$mergeable" = "MERGEABLE" ] || echo "mergeable: $mergeable"
  [ "$decision" = "CHANGES_REQUESTED" ] && echo "review: changes requested"
  printf '%s' "$json" | jq -r '.statusCheckRollup[]? | select(.conclusion=="FAILURE" or .conclusion=="CANCELLED" or (.status=="IN_PROGRESS")) | "check: \(.name) \(.conclusion // .status)"'
  return 0
}

pr_review() {
  local url=$1 verdict=$2 body=$3
  command -v gh >/dev/null 2>&1 || { echo "chief-pr-provider-github: gh is required" >&2; return 1; }
  case "$verdict" in
    comment) gh pr review "$url" --comment --body "$body" ;;
    request-changes) gh pr review "$url" --request-changes --body "$body" ;;
    *) echo "chief-pr-provider-github: unknown verdict '$verdict'" >&2; return 1 ;;
  esac
}

pr_approve() {
  local url=$1
  command -v gh >/dev/null 2>&1 || { echo "chief-pr-provider-github: gh is required" >&2; return 1; }
  gh pr review "$url" --approve
}

pr_merge() {
  local url=$1
  shift
  local method="--squash"
  case "${1:-}" in
    --squash|--merge|--rebase) method=$1 ;;
    "") ;;
    *) echo "chief-pr-provider-github: unknown merge method '$1'" >&2; return 1 ;;
  esac
  command -v gh >/dev/null 2>&1 || { echo "chief-pr-provider-github: gh is required" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "chief-pr-provider-github: jq is required" >&2; return 1; }
  local json state mergeable draft head decision
  json=$(gh pr view "$url" --json state,mergeable,isDraft,headRefOid,statusCheckRollup,reviewDecision) \
    || { echo "chief-pr-provider-github: could not read PR state for $url" >&2; return 1; }
  state=$(printf '%s' "$json" | jq -r .state)
  mergeable=$(printf '%s' "$json" | jq -r .mergeable)
  draft=$(printf '%s' "$json" | jq -r .isDraft)
  head=$(printf '%s' "$json" | jq -r .headRefOid)
  decision=$(printf '%s' "$json" | jq -r .reviewDecision)
  [ "$state" = "OPEN" ] || { echo "chief-pr-provider-github: PR is $state, not OPEN" >&2; return 1; }
  [ "$draft" = "false" ] || { echo "chief-pr-provider-github: PR is still a draft" >&2; return 1; }
  [ "$mergeable" = "MERGEABLE" ] || { echo "chief-pr-provider-github: PR is not mergeable (reported: $mergeable)" >&2; return 1; }
  [ "$decision" != "CHANGES_REQUESTED" ] || { echo "chief-pr-provider-github: PR has changes requested" >&2; return 1; }
  local blocking
  blocking=$(printf '%s' "$json" | jq -r '.statusCheckRollup[]? | select(.conclusion=="FAILURE" or .conclusion=="CANCELLED" or (.status=="IN_PROGRESS")) | "\(.name) \(.conclusion // .status)"')
  [ -z "$blocking" ] || { echo "chief-pr-provider-github: PR has blocking checks: $blocking" >&2; return 1; }
  gh pr merge "$url" "$method" --match-head-commit "$head"
}
