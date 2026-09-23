#!/usr/bin/env bash
# chief-pr-open.sh - push a task's branch and open a PR/MR for it, then
# record the result on the task so review/approve/state/merge can find it.
# Requires --confirm - only pass it once the operator has explicitly said to
# open a PR for <id>. Ship agents never do this themselves (see
# templates/brief-ship.md rule 1).
#
# Usage: chief-pr-open.sh <id> --confirm [--title "..."] [--body "..."]
#   Defaults title/body from the task's brief.md '## Operator's intent'
#   section when not given explicitly.
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"
. "$CHIEF_ROOT/bin/lib/chief-pr-provider.sh"

fail() { echo "chief-pr-open: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-pr-open.sh <id> --confirm [--title \"...\"] [--body \"...\"]"
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
[ "$CONFIRMED" -eq 1 ] || fail "refusing to open a PR without --confirm - only pass it once the operator has explicitly said to open a PR for $ID in this conversation"

EXISTING=$(chief_meta_get "$ID" pr_url 2>/dev/null || true)
[ -z "$EXISTING" ] || fail "PR already open: $EXISTING - use chief-pr-state.sh to check it"

MODE=$(chief_meta_get "$ID" mode 2>/dev/null || true)
[ "$MODE" = "ship" ] || fail "$ID is not a ship task (mode=${MODE:-unknown}) - only a ship task's branch is meant to be pushed and opened as a PR/MR"

PROJECT=$(chief_meta_require "$ID" project)
BRANCH=$(chief_meta_require "$ID" branch)
WORKTREE=$(chief_meta_require "$ID" worktree)

[ -z "$(git -C "$WORKTREE" status --porcelain 2>/dev/null)" ] \
  || fail "$WORKTREE has uncommitted changes; commit or discard them before opening a PR"

DEFAULT=$(git -C "$PROJECT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || true
[ -n "$DEFAULT" ] || DEFAULT=$(git -C "$PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null || echo main)

extract_intent() {
  [ -f "$1" ] || return 0
  awk '/^## Operator.s intent$/ { flag=1; next } /^## / { flag=0 } flag' "$1"
}

BRIEF="$DATA/$ID/brief.md"
if [ -z "$TITLE" ]; then
  # Default from the branch's own commit history, not the intent text - a
  # title that just echoes the intent duplicates what BODY already says.
  SUBJECTS=$(git -C "$WORKTREE" log --reverse --format=%s "$DEFAULT..$BRANCH" 2>/dev/null || true)
  SUBJECT_COUNT=$(printf '%s\n' "$SUBJECTS" | grep -c . || true)
  if [ "$SUBJECT_COUNT" -eq 1 ]; then
    TITLE=$SUBJECTS
  elif [ "$SUBJECT_COUNT" -gt 1 ]; then
    TITLE="$(printf '%s\n' "$SUBJECTS" | head -n1) (+$((SUBJECT_COUNT - 1)) more)"
  fi
  [ -n "$TITLE" ] || TITLE="chief: $ID"
fi
if [ -z "$BODY" ]; then
  BODY=$(extract_intent "$BRIEF" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  [ -n "$BODY" ] || BODY="(see $DATA/$ID/report.md)"
fi

git -C "$WORKTREE" push -q -u origin "$BRANCH" || fail "push failed for $BRANCH"

PROVIDER=$(chief_pr_detect_provider "$WORKTREE") || exit 1
chief_pr_load_provider "$PROVIDER" || exit 1

URL=$(cd "$WORKTREE" && pr_open "$BRANCH" "$DEFAULT" "$TITLE" "$BODY") || fail "provider failed to open a PR"
[ -n "$URL" ] || fail "provider returned no PR URL"
case "$URL" in
  http*) ;;
  *) fail "provider returned something that doesn't look like a URL: $URL" ;;
esac
[ "$(printf '%s' "$URL" | wc -l)" -le 0 ] || fail "provider returned more than one line: $URL"

chief_meta_set "$ID" pr_url "$URL"
chief_meta_set "$ID" pr_provider "$PROVIDER"
# Opening the PR is the normal flow acting on this task - take it out of
# chief-watch.sh's in_flight_ids so it stops re-notifying about the same
# already-surfaced terminal state on every subsequent Stop hook.
chief_meta_set "$ID" status pr-opened
"$CHIEF_ROOT/bin/chief-backlog.sh" note "$ID" "opened PR: $URL" 2>/dev/null || true

echo "opened: $ID -> $URL ($PROVIDER)"
