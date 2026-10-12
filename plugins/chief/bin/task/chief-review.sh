#!/usr/bin/env bash
# chief-review.sh - start or re-arm a builder's reviewer on its latest commit.
# Round 1 files and spawns <builder>-review; later rounds archive its report,
# message it and re-arm it. It never reads a verdict or forwards findings.
#
# Usage: chief-review.sh <builder-id>
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/../lib/paths.sh"
. "$CHIEF_ROOT/bin/lib/meta.sh"

fail() { echo "chief-review: $*" >&2; exit 1; }

BID=${1:-}
[ -n "$BID" ] || fail "usage: chief-review.sh <builder-id>"
chief_meta_exists "$BID" || fail "no such task: $BID"
[ "$(chief_meta_get "$BID" mode 2>/dev/null)" = builder ] || fail "$BID is not a builder"

LAST=$(tail -n 1 "$STATE/$BID.status" 2>/dev/null || true)
[[ $LAST == done:* ]] || fail "$BID is not done (last status: ${LAST:-none})"
PROJECT=$(chief_meta_require "$BID" project)
WORKTREE=$(chief_meta_require "$BID" worktree)
BRANCH=$(chief_meta_require "$BID" branch)
[ -z "$(git -C "$WORKTREE" status --porcelain)" ] || fail "$BID's worktree is not clean"
BASE=$(git -C "$PROJECT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || true
[ -n "$BASE" ] || BASE=$(git -C "$PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null || echo main)
SHA=$(git -C "$WORKTREE" rev-parse HEAD)
[ "$(git -C "$WORKTREE" rev-list --count "$BASE..$SHA")" -gt 0 ] || fail "$BID has no commit ahead of $BASE"

RID=$BID-review
ROUND=1
LINKED=$(chief_meta_get "$BID" reviewer 2>/dev/null || true)
if [ -n "$LINKED" ]; then
  [ -d "$(chief_meta_get "$RID" worktree 2>/dev/null)" ] || fail "reviewer $RID was torn down"
  if [ "$SHA" = "$(chief_meta_get "$BID" review_sha 2>/dev/null)" ] \
    && [[ $("$CHIEF_ROOT/bin/task/chief-crew-state.sh" "$RID") == "state: working"* ]]; then
    fail "$RID is already reviewing ${SHA:0:7}"
  fi
  ROUND=$(( $(chief_meta_get "$BID" review_round) + 1 ))
fi

text="Review round $ROUND. Branch: $BRANCH. Pinned SHA: $SHA. Base: $BASE.
Builder brief (intent): $DATA/$BID/brief.md
Builder done line: ${LAST#done: }"

if [ "$ROUND" -eq 1 ]; then
  if [ -z "$("$CHIEF_ROOT/bin/chief-backlog.sh" show "$RID")" ]; then
    title=$("$CHIEF_ROOT/bin/chief-backlog.sh" show "$BID" | sed -n '1s/^## [^ ]* \[[a-z-]*\] //; 1s/ \[agent: [^]]*\]$//p')
    "$CHIEF_ROOT/bin/chief-backlog.sh" add "$RID" "review of $BID: $title" >/dev/null
  fi
  "$CHIEF_ROOT/bin/chief-spawn.sh" "$RID" "$PROJECT" --mode reviewer --branch "chore/review-$BID" \
    --intent "Review $BID" --spec "$text"
else
  [ ! -f "$DATA/$RID/report.md" ] || mv "$DATA/$RID/report.md" "$DATA/$RID/report.round-$((ROUND - 1)).md"
  priors=$(ls "$DATA/$RID"/report.round-*.md 2>/dev/null || true)
  "$CHIEF_ROOT/bin/task/chief-send.sh" "$RID" "$text
Earlier reports (to verify, not to repeat):
$priors"
  "$CHIEF_ROOT/bin/chief-backlog.sh" status "$RID" in-flight >/dev/null
  echo "working: round $ROUND requested" >> "$STATE/$RID.status"
  touch "$STATE/$RID.turn-ended"
fi

chief_meta_set "$RID" for "$BID"
chief_meta_set "$BID" reviewer "$RID"
chief_meta_set "$BID" review_round "$ROUND"
chief_meta_set "$BID" review_sha "$SHA"
echo "review: $RID round $ROUND of $BID @${SHA:0:7}"
