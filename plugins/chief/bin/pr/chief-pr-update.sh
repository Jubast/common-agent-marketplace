#!/usr/bin/env bash
# chief-pr-update.sh - push a task's branch's new commits and, when given,
# refresh its already-open PR/MR's title/body. Requires --confirm the same
# way chief-pr-open.sh does. Ship agents never do this themselves (see
# templates/brief-ship.md rule 1).
#
# --title/--body are OPTIONAL here (unlike chief-pr-open.sh, where they're
# required): a plain push-only update with no description change is a
# legitimate use, e.g. a follow-up commit after review feedback.
#
# Usage: chief-pr-update.sh <id> --confirm [--title "..."] [--body "..."]
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/../lib/paths.sh"
. "$CHIEF_ROOT/bin/lib/meta.sh"
. "$CHIEF_ROOT/bin/lib/pr-providers/pr-provider.sh"

fail() { echo "chief-pr-update: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-pr-update.sh <id> --confirm [--title \"...\"] [--body \"...\"]"
chief_meta_exists "$ID" || fail "no such task: $ID"
shift

TITLE=""
BODY=""
CONFIRMED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm) CONFIRMED=1; shift ;;
    --title) TITLE=${2:-}; shift 2 ;;
    --body) BODY=${2:-}; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[ "$CONFIRMED" -eq 1 ] || fail "refusing to update a PR without --confirm - only pass it once the operator has explicitly said to update $ID's PR in this conversation"

URL=$(chief_meta_get "$ID" pr_url 2>/dev/null || true)
[ -n "$URL" ] || fail "no PR open yet for $ID - use chief-pr-open.sh to open one first"
PROVIDER=$(chief_meta_require "$ID" pr_provider)

BRANCH=$(chief_meta_require "$ID" branch)
WORKTREE=$(chief_meta_require "$ID" worktree)

[ -z "$(git -C "$WORKTREE" status --porcelain 2>/dev/null)" ] \
  || fail "$WORKTREE has uncommitted changes; commit or discard them before updating the PR"

git -C "$WORKTREE" push -q -u origin "$BRANCH" || fail "push failed for $BRANCH"

chief_pr_load_provider "$PROVIDER" || exit 1

if [ -n "$TITLE" ] || [ -n "$BODY" ]; then
  pr_update "$URL" "$TITLE" "$BODY" || fail "provider failed to update the PR"
fi

echo "updated: $ID -> $URL ($PROVIDER)"
