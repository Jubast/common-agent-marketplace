#!/usr/bin/env bash
# chief-merge.sh - the ONLY merge path. Always operator-invoked; there is no
# yolo/auto-merge in this plugin, on purpose - a human runs this command.
#
# Usage: chief-merge.sh <id>              -> local git merge --ff-only
#        chief-merge.sh <id> --pr <url>   -> gh pr merge --squash after
#                                            confirming every check is green
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"

fail() { echo "chief-merge: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-merge.sh <id> [--pr <url>]"
chief_meta_exists "$ID" || fail "no such task: $ID"
shift

PR_URL=""
if [ "${1:-}" = "--pr" ]; then
  PR_URL=${2:-}
  [ -n "$PR_URL" ] || fail "--pr requires a URL"
fi

PROJECT=$(chief_meta_require "$ID" project)
BRANCH=$(chief_meta_require "$ID" branch)

if [ -n "$PR_URL" ]; then
  command -v gh >/dev/null 2>&1 || fail "gh is required for --pr merges"
  STATE_JSON=$(gh pr view "$PR_URL" --json state,mergeable,isDraft) \
    || fail "could not read PR state for $PR_URL"
  state=$(printf '%s' "$STATE_JSON" | jq -r .state)
  mergeable=$(printf '%s' "$STATE_JSON" | jq -r .mergeable)
  draft=$(printf '%s' "$STATE_JSON" | jq -r .isDraft)
  [ "$state" = "OPEN" ]      || fail "PR is $state, not OPEN"
  [ "$draft" = "false" ]     || fail "PR is still a draft"
  [ "$mergeable" = "MERGEABLE" ] || fail "PR is not mergeable (reported: $mergeable)"
  gh pr merge "$PR_URL" --squash || fail "gh pr merge failed"
  echo "merged: $ID via PR $PR_URL"
  exit 0
fi

DEFAULT=$(git -C "$PROJECT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || true
[ -n "$DEFAULT" ] || DEFAULT=$(git -C "$PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null || echo main)

CUR=$(git -C "$PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
[ "$CUR" = "$DEFAULT" ] || fail "$PROJECT is on '$CUR', expected default branch '$DEFAULT'"
[ -z "$(git -C "$PROJECT" status --porcelain 2>/dev/null)" ] || fail "$PROJECT has a dirty working tree; refusing to merge into it"

git -C "$PROJECT" merge-base --is-ancestor "$DEFAULT" "$BRANCH" \
  || fail "REFUSED: $BRANCH is not a fast-forward of $DEFAULT (it has diverged) - rebase the builder's branch first"

git -C "$PROJECT" merge --ff-only "$BRANCH" || fail "fast-forward merge failed"
echo "merged: $ID -> $DEFAULT in $PROJECT (fast-forward)"
