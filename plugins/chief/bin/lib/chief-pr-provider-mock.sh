#!/usr/bin/env bash
# chief-pr-provider-mock.sh - DEV/TEST ONLY fake PR provider. No network, no
# real CLI. Every call is appended to $CHIEF_PR_MOCK_LOG (if set) so tests can
# assert exactly what each chief-pr-*.sh script asked the provider to do.
# Behavior is steered by env vars so a test can simulate blockers/failures
# without a real forge:
#   CHIEF_PR_MOCK_URL        - URL pr_open returns (default: a canned URL)
#   CHIEF_PR_MOCK_STATE      - newline-separated lines pr_state prints
#   CHIEF_PR_MOCK_MERGE_FAIL - when "1", pr_merge refuses (simulates a
#                              precondition failure) instead of succeeding

_chief_pr_mock_log() {
  [ -n "${CHIEF_PR_MOCK_LOG:-}" ] && printf '%s\n' "$*" >> "$CHIEF_PR_MOCK_LOG"
  return 0
}

pr_open() {
  local branch=$1 base=$2 title=$3 body=$4
  _chief_pr_mock_log "pr_open $branch $base $title $body"
  printf '%s\n' "${CHIEF_PR_MOCK_URL:-https://example.invalid/mock/pr/1}"
}

pr_state() {
  local url=$1
  _chief_pr_mock_log "pr_state $url"
  [ -n "${CHIEF_PR_MOCK_STATE:-}" ] && printf '%s\n' "$CHIEF_PR_MOCK_STATE"
  return 0
}

pr_review() {
  local url=$1 verdict=$2 body=$3
  _chief_pr_mock_log "pr_review $url $verdict $body"
}

pr_approve() {
  local url=$1
  _chief_pr_mock_log "pr_approve $url"
}

pr_merge() {
  local url=$1
  shift
  # No default here - chief-pr-merge.sh always passes one explicitly.
  local method=${1:?chief-pr-provider-mock: pr_merge called with no method}
  _chief_pr_mock_log "pr_merge $url $method"
  if [ "${CHIEF_PR_MOCK_MERGE_FAIL:-0}" = "1" ]; then
    echo "chief-pr-provider-mock: simulated merge refusal" >&2
    return 1
  fi
}
