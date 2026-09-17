#!/usr/bin/env bash
# chief-pr-provider-gitlab.sh - GitLab adapter, backed by `glab`.
#
# GitLab's MR model has no GitHub-style "request changes" review state - an
# MR either has approvals or it doesn't, and reviewer feedback is just a
# note/comment. So pr_review posts the same kind of note for both verdicts;
# the request-changes/comment distinction is preserved by chief-pr-review.sh
# in its own stdout message, but there is nothing provider-side to route it
# to differently.

pr_open() {
  local branch=$1 base=$2 title=$3 body=$4
  command -v glab >/dev/null 2>&1 || { echo "chief-pr-provider-gitlab: glab is required" >&2; return 1; }
  local out
  out=$(glab mr create --source-branch "$branch" --target-branch "$base" --title "$title" --description "$body" --yes) || return 1
  printf '%s\n' "$out" | grep -Eo 'https?://[^[:space:]]+/merge_requests/[0-9]+' | tail -1
}

pr_state() {
  local url=$1
  command -v glab >/dev/null 2>&1 || { echo "chief-pr-provider-gitlab: glab is required" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "chief-pr-provider-gitlab: jq is required" >&2; return 1; }
  local json state draft mergeable
  json=$(glab mr view "$url" -F json) || return 1
  state=$(printf '%s' "$json" | jq -r '.state')
  [ "$state" = "opened" ] || { echo "state: $state"; return 0; }
  draft=$(printf '%s' "$json" | jq -r '.draft')
  mergeable=$(printf '%s' "$json" | jq -r '.detailed_merge_status')
  [ "$draft" = "true" ] && echo "draft: still a draft MR"
  [ "$mergeable" = "mergeable" ] || echo "mergeable: $mergeable"
  return 0
}

pr_review() {
  local url=$1 verdict=$2 body=$3
  command -v glab >/dev/null 2>&1 || { echo "chief-pr-provider-gitlab: glab is required" >&2; return 1; }
  case "$verdict" in
    comment|request-changes) glab mr note "$url" --message "$body" ;;
    *) echo "chief-pr-provider-gitlab: unknown verdict '$verdict'" >&2; return 1 ;;
  esac
}

pr_approve() {
  local url=$1
  command -v glab >/dev/null 2>&1 || { echo "chief-pr-provider-gitlab: glab is required" >&2; return 1; }
  glab mr approve "$url"
}

pr_merge() {
  local url=$1
  shift
  local -a extra=()
  case "${1:-}" in
    --squash) extra=(--squash) ;;
    --rebase) extra=(--rebase) ;;
    --merge|"") extra=() ;;
    *) echo "chief-pr-provider-gitlab: unknown merge method '$1'" >&2; return 1 ;;
  esac
  command -v glab >/dev/null 2>&1 || { echo "chief-pr-provider-gitlab: glab is required" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "chief-pr-provider-gitlab: jq is required" >&2; return 1; }
  local json state draft mergeable
  json=$(glab mr view "$url" -F json) || { echo "chief-pr-provider-gitlab: could not read MR state for $url" >&2; return 1; }
  state=$(printf '%s' "$json" | jq -r '.state')
  draft=$(printf '%s' "$json" | jq -r '.draft')
  mergeable=$(printf '%s' "$json" | jq -r '.detailed_merge_status')
  [ "$state" = "opened" ] || { echo "chief-pr-provider-gitlab: MR is $state, not opened" >&2; return 1; }
  [ "$draft" = "false" ] || { echo "chief-pr-provider-gitlab: MR is still a draft" >&2; return 1; }
  [ "$mergeable" = "mergeable" ] || { echo "chief-pr-provider-gitlab: MR is not mergeable (reported: $mergeable)" >&2; return 1; }
  glab mr merge "$url" "${extra[@]}" --yes
}
