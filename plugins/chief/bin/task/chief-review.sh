#!/usr/bin/env bash
# chief-review.sh - start or re-arm a builder's reviewers on its latest commit.
# Each review arms the pool entries its mode picks: a new one is spawned as
# <builder>-rv (<builder>-rv-<n> for entry n of a pool), an existing one is
# re-armed (its report archived, a message sent). It never reads a verdict or
# forwards findings and never waits: Chief drives a sequential review by
# running it once per entry.
#
# Usage: chief-review.sh <builder-id> [--mode parallel|sequential|first] [--only <n>[,<n>...]]
#   --mode  overrides the [reviewer] mode of .chief/config/agents (default parallel)
#   --only  the pool entries (1-based, in file order) to arm instead of the mode's own
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/../lib/paths.sh"
. "$CHIEF_ROOT/bin/lib/meta.sh"
. "$CHIEF_ROOT/bin/lib/id.sh"
. "$CHIEF_ROOT/bin/lib/agents/agent.sh"

fail() { echo "chief-review: $*" >&2; exit 1; }

USAGE="usage: chief-review.sh <builder-id> [--mode parallel|sequential|first] [--only <n>[,<n>...]]"
BID=${1:-}
[ -n "$BID" ] || fail "$USAGE"
shift
MODE="" ONLY=""
while [ $# -gt 0 ]; do
  case $1 in
    --mode) [ $# -ge 2 ] || fail "$USAGE"; MODE=$2; shift 2 ;;
    --only) [ $# -ge 2 ] || fail "$USAGE"; ONLY=$2; shift 2 ;;
    *) fail "$USAGE" ;;
  esac
done
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

# --- what to arm ------------------------------------------------------------
[ -n "$MODE" ] || MODE=$(chief_agent_review_mode) || fail "cannot read the [reviewer] config"
case $MODE in
  parallel|sequential|first) ;;
  ask) fail "mode is ask: ask the operator for the mode and pool entries, then pass --mode and --only" ;;
  *) fail "unknown mode '$MODE' (parallel, sequential or first)" ;;
esac
PICKS=$(chief_agent_review_picks "$MODE" "$ONLY") || exit 1
POOL_N=$(chief_agent_pool_size reviewer)

# Each linked reviewer records the pool entry it runs (pick) and the round and
# commit it was last armed on (armed=<round>@<sha>). A pick with a live
# reviewer is re-armed, one with none is spawned, a torn-down one is skipped.
LINKED=$(chief_meta_get "$BID" reviewer 2>/dev/null || true)
REARM="" SPAWN=""
for PICK in $PICKS; do
  FOUND=""
  for RID in $LINKED; do
    [ "$(chief_meta_get "$RID" pick 2>/dev/null)" = "$PICK" ] && FOUND=$RID
  done
  if [ -z "$FOUND" ]; then SPAWN+="${SPAWN:+ }$PICK"
  elif [ "$(chief_meta_get "$FOUND" status 2>/dev/null)" != torn-down ]; then REARM+="${REARM:+ }$FOUND"
  fi
done
if [ -n "$LINKED" ]; then
  [ -n "$REARM$SPAWN" ] || fail "reviewer(s) $LINKED torn down: nothing to run"
fi

# Round 1 is the first arming. A later one is a new round, unless the commit is
# the one of the last arming and no re-armed reviewer has reviewed it yet (the
# next entry of a sequential run).
ROUND=1
if [ -n "$LINKED" ]; then
  PRIOR=$(chief_meta_get "$BID" review_round 2>/dev/null || true)
  ROUND=$((PRIOR + 1))
  CONTINUES=0
  [ "$SHA" = "$(chief_meta_get "$BID" review_sha 2>/dev/null || true)" ] && CONTINUES=1
  for RID in $REARM; do
    ARMED=$(chief_meta_get "$RID" armed 2>/dev/null || true)
    if [ "${ARMED#*@}" = "$SHA" ]; then
      CONTINUES=0
      [[ $("$CHIEF_ROOT/bin/task/chief-crew-state.sh" "$RID") != "state: working"* ]] || fail "$RID is already reviewing ${SHA:0:7}"
    fi
  done
  [ "$CONTINUES" = 1 ] && ROUND=$PRIOR
fi

text="Review round $ROUND. Branch: $BRANCH. Pinned SHA: $SHA. Base: $BASE.
Builder brief (intent): $(chief_task_path "$BID" brief.md)
Builder done line: ${LAST#done: }
Builder DoD evidence: $(chief_task_path "$BID" report.md) (absent if there are no DoD items)"

# --- arm ---------------------------------------------------------------------
# The builder's links are written after each spawn, so a killed run leaves its
# reviewers linked and the round recorded.
NEW=""  # spawned by this run, discarded again if a spawn fails
OLD_ROUND=$(chief_meta_get "$BID" review_round 2>/dev/null || true)
OLD_SHA=$(chief_meta_get "$BID" review_sha 2>/dev/null || true)
if [ -n "$SPAWN" ]; then
  title=$("$CHIEF_ROOT/bin/chief-backlog.sh" show "$BID" | sed -n '1s/^## [^ ]* \[[a-z-]*\] //; 1s/ \[agent: [^]]*\]$//p')
  for PICK in $SPAWN; do
    RID=$(chief_id_compose "$BID" "rv$([ "$PICK" = 0 ] || [ "$POOL_N" -le 1 ] || echo "-$PICK")")
    [ -n "$("$CHIEF_ROOT/bin/chief-backlog.sh" show "$RID")" ] \
      || "$CHIEF_ROOT/bin/chief-backlog.sh" add "$RID" "review of $BID: $title" >/dev/null
    # One reviewer at a time: chief-spawn.sh returns only once the reviewer's first turn started.
    if ! CHIEF_EVIDENCE_MOVED= CHIEF_AGENT_PICK=$([ "$PICK" = 0 ] || echo "$PICK") "$CHIEF_ROOT/bin/chief-spawn.sh" "$RID" "$PROJECT" --mode reviewer --branch "chore/$RID" \
      --intent "Review $BID" --spec "$text"; then
      # nothing queued or left behind for the failed one; its evidence moves to the builder
      kept=""; stamp=$(date -u +%Y%m%dT%H%M%S)-$$
      for f in "$(chief_task_path "$RID" evidence)"/*spawn-screen.*.txt; do
        [ -f "$f" ] || continue
        mkdir -p "$(chief_task_path "$BID" evidence)"
        mv "$f" "$(chief_task_path "$BID" evidence)/$RID-$stamp-${f##*/}"; kept=1
      done
      { chief_meta_exists "$RID" || [ -e "$(chief_task_path "$RID" spawning)" ]; } || rm -rf "$(chief_task_dir "$RID")"
      "$CHIEF_ROOT/bin/chief-backlog.sh" drop "$RID" >/dev/null 2>&1 || true  # queued records only
      for r in $NEW; do "$CHIEF_ROOT/bin/chief-teardown.sh" "$r" --abandon >/dev/null 2>&1 || true; done
      chief_meta_set "$BID" reviewer "$LINKED"
      chief_meta_set "$BID" review_round "$OLD_ROUND"
      chief_meta_set "$BID" review_sha "$OLD_SHA"
      fail "spawning reviewer $RID failed; the reviewers started are discarded, retry the review${kept:+; spawn screens kept in $(chief_task_path "$BID" evidence)/ as $RID-*-spawn-screen.*.txt}"
    fi
    chief_meta_set "$RID" for "$BID"
    chief_meta_set "$RID" pick "$PICK"
    chief_meta_set "$RID" armed "$ROUND@$SHA"
    NEW+="${NEW:+ }$RID"
    chief_meta_set "$BID" reviewer "${LINKED:+$LINKED }$NEW"
    chief_meta_set "$BID" review_round "$ROUND"
    chief_meta_set "$BID" review_sha "$SHA"
  done
fi
for RID in $REARM; do
  REPORT=$(chief_task_path "$RID" report.md)
  ARMED=$(chief_meta_get "$RID" armed 2>/dev/null || echo "$((ROUND - 1))@")
  [ ! -f "$REPORT" ] || mv "$REPORT" "${REPORT%.md}.round-${ARMED%@*}.md"
  priors=$(ls "${REPORT%.md}".round-*.md 2>/dev/null || true)
  "$CHIEF_ROOT/bin/task/chief-send.sh" "$RID" "$text
Earlier reports (to verify, not to repeat):
$priors"
  "$CHIEF_ROOT/bin/chief-backlog.sh" status "$RID" in-flight >/dev/null
  echo "working: round $ROUND requested" >> "$(chief_task_path "$RID" status)"
  touch "$(chief_task_path "$RID" turn-ended)"
  chief_meta_set "$RID" armed "$ROUND@$SHA"
done

chief_meta_set "$BID" review_round "$ROUND"
chief_meta_set "$BID" review_sha "$SHA"
RAN="$NEW${NEW:+${REARM:+ }}$REARM"
echo "review: ${RAN// /, } round $ROUND of $BID @${SHA:0:7}"
if [ "$MODE" = sequential ] && [ "$PICKS" != 0 ]; then
  if [ "$PICKS" -lt "$POOL_N" ]; then
    echo "sequential: entry $PICKS of $POOL_N; on PASS run: chief-review.sh $BID --mode sequential --only $((PICKS + 1))"
  else
    echo "sequential: entry $PICKS of $POOL_N, the last"
  fi
fi
