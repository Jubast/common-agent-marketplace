#!/usr/bin/env bash
# chief-review.sh - start or re-arm a builder's reviewers on its latest commit.
# Round 1 files and spawns <builder>-rv (<builder>-rv-1, -2... under strategy
# all); later rounds archive each report, message and re-arm each reviewer.
# It never reads a verdict or forwards findings.
#
# Usage: chief-review.sh <builder-id>
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/../lib/paths.sh"
. "$CHIEF_ROOT/bin/lib/meta.sh"
. "$CHIEF_ROOT/bin/lib/id.sh"
. "$CHIEF_ROOT/bin/lib/agents/agent.sh"

fail() { echo "chief-review: $*" >&2; exit 1; }

BID=${1:-}
[ -n "$BID" ] || fail "usage: chief-review.sh <builder-id>"
chief_meta_exists "$BID" || fail "no such task: $BID"
[ "$(chief_meta_get "$BID" mode 2>/dev/null)" = builder ] || fail "$BID is not a builder"

LAST=$(tail -n 1 "$(chief_task_path "$BID" status)" 2>/dev/null || true)
[[ $LAST == done:* ]] || fail "$BID is not done (last status: ${LAST:-none})"
PROJECT=$(chief_meta_require "$BID" project)
WORKTREE=$(chief_meta_require "$BID" worktree)
BRANCH=$(chief_meta_require "$BID" branch)
[ -z "$(git -C "$WORKTREE" status --porcelain)" ] || fail "$BID's worktree is not clean"
BASE=$(git -C "$PROJECT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || true
[ -n "$BASE" ] || BASE=$(git -C "$PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null || echo main)
SHA=$(git -C "$WORKTREE" rev-parse HEAD)
[ "$(git -C "$WORKTREE" rev-list --count "$BASE..$SHA")" -gt 0 ] || fail "$BID has no commit ahead of $BASE"
DONE_SHA=${LAST#done: }; DONE_SHA=${DONE_SHA%% *}
{ [ "${#DONE_SHA}" -ge 7 ] && [[ $SHA == "$DONE_SHA"* ]]; } \
  || fail "$BID's done line does not start with HEAD's SHA ${SHA:0:7} (it committed after reporting done, or the line has no SHA)"

ROUND=1
LINKED=$(chief_meta_get "$BID" reviewer 2>/dev/null || true)
LIVE=""
for RID in $LINKED; do [ "$(chief_meta_get "$RID" status 2>/dev/null)" = torn-down ] || LIVE+="${LIVE:+ }$RID"; done
if [ -n "$LINKED" ]; then
  [ -n "$LIVE" ] || fail "reviewer $LINKED was torn down"
  for RID in $LIVE; do
    if [ "$SHA" = "$(chief_meta_get "$BID" review_sha 2>/dev/null)" ] \
      && [[ $("$CHIEF_ROOT/bin/task/chief-crew-state.sh" "$RID") == "state: working"* ]]; then
      fail "$RID is already reviewing ${SHA:0:7}"
    fi
  done
  ROUND=$(( $(chief_meta_get "$BID" review_round) + 1 ))
fi

text="Review round $ROUND. Branch: $BRANCH. Pinned SHA: $SHA. Base: $BASE.
Builder brief (intent): $(chief_task_path "$BID" brief.md)
Builder done line: ${LAST#done: }
Builder DoD evidence: $(chief_task_path "$BID" report.md) (absent if there are no DoD items)"

if [ "$ROUND" -eq 1 ]; then
  # One reviewer per [reviewer] entry under strategy all (<builder>-rv-<n>), else <builder>-rv.
  N=$(chief_agent_count reviewer) || fail "cannot read the [reviewer] pool"
  title=$("$CHIEF_ROOT/bin/chief-backlog.sh" show "$BID" | sed -n '1s/^## [^ ]* \[[a-z-]*\] //; 1s/ \[agent: [^]]*\]$//p')
  for PICK in $(seq "$N"); do
    RID=$(chief_id_compose "$BID" "rv$([ "$N" = 1 ] || echo "-$PICK")")
    [ -n "$("$CHIEF_ROOT/bin/chief-backlog.sh" show "$RID")" ] \
      || "$CHIEF_ROOT/bin/chief-backlog.sh" add "$RID" "review of $BID: $title" >/dev/null
    if ! CHIEF_AGENT_PICK=$PICK "$CHIEF_ROOT/bin/chief-spawn.sh" "$RID" "$PROJECT" --mode reviewer --branch "chore/$RID" \
      --intent "Review $BID" --spec "$text"; then
      for r in $LIVE; do "$CHIEF_ROOT/bin/chief-teardown.sh" "$r" --abandon >/dev/null 2>&1 || true; done
      fail "spawning reviewer $RID failed; nothing is linked, retry the review"
    fi
    chief_meta_set "$RID" for "$BID"
    LIVE+="${LIVE:+ }$RID"
  done
  chief_meta_set "$BID" reviewer "$LIVE"
else
  for RID in $LIVE; do
    REPORT=$(chief_task_path "$RID" report.md)
    [ ! -f "$REPORT" ] || mv "$REPORT" "${REPORT%.md}.round-$((ROUND - 1)).md"
    priors=$(ls "${REPORT%.md}".round-*.md 2>/dev/null || true)
    "$CHIEF_ROOT/bin/task/chief-send.sh" "$RID" "$text
Earlier reports (to verify, not to repeat):
$priors"
    "$CHIEF_ROOT/bin/chief-backlog.sh" status "$RID" in-flight >/dev/null
    echo "working: round $ROUND requested" >> "$(chief_task_path "$RID" status)"
    touch "$(chief_task_path "$RID" turn-ended)"
  done
fi

chief_meta_set "$BID" review_round "$ROUND"
chief_meta_set "$BID" review_sha "$SHA"
echo "review: ${LIVE// /, } round $ROUND of $BID @${SHA:0:7}"
