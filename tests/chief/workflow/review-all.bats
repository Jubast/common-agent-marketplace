# chief-review.sh with `strategy = all` on a real herdr: one reviewer per entry
# of the [reviewer] pool, one watcher wake per round, and how a failed, torn-down
# or never-started reviewer is treated.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  chief_herdr_server
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
  RV="$BIN/task/chief-review.sh"
  BL="$BIN/chief-backlog.sh"
  mkdir -p "$CHIEF_HOME/config"
  printf '[reviewer]\nstrategy = all\nclaude:sonnet\nclaude:haiku\n' > "$CHIEF_HOME/config/agents"
}

teardown() { chief_herdr_stop; }

review() { timeout 90 "$RV" "$@" 2>&1; }
rwork() { echo "working: reviewing" >> "$TASKS/$1/status"; touch "$TASKS/$1/turn-ended"; }
rdone() { echo "done: round $2 PASS @x" >> "$TASKS/$1/status"; }  # <reviewer> <round>

# round_one - b-4 done, both reviewers started and working; the builder held
round_one() {
  chief_done_builder b-4
  review b-4 >/dev/null
  "$BL" hold b-4 reported >/dev/null
  rwork b-4-rv-1; rwork b-4-rv-2
}

# next_round [reviewer...] - the builder fixes and reports again, the next round
# starts and the reviewers (default both) settle
next_round() {
  local r s rs=("$@")
  [ ${#rs[@]} -gt 0 ] || rs=(b-4-rv-1 b-4-rv-2)
  s=$(commit_file b-4 "r$RANDOM.txt")
  echo "done: ${s:0:7} fixed" >> "$TASKS/b-4/status"
  run review b-4
  "$BL" hold b-4 reported >/dev/null
  for r in "${rs[@]}"; do wait_settled "$r"; done
}

@test "round 1: starts one reviewer per entry and links them to the builder" {
  chief_done_builder b-4
  run review b-4
  assert_output --partial "review: b-4-rv-1, b-4-rv-2 round 1 of b-4"
  assert_equal "$(chief_meta_get b-4 reviewer)" "b-4-rv-1 b-4-rv-2"
  assert_equal "$(chief_meta_get b-4-rv-1 model):$(chief_meta_get b-4-rv-2 model)" "sonnet:haiku"
  assert_equal "$(chief_meta_get b-4-rv-2 for)" b-4
}

@test "watch: the first done stays quiet while a sibling works and the last wakes Chief" {
  round_one
  rdone b-4-rv-1 1
  watch_silent
  rdone b-4-rv-2 1
  watch_once
  assert_output --partial "b-4-rv-2: state: done"
  watch_silent
}

@test "round 2: every reviewer gets the new SHA and finishing together wakes once" {
  round_one
  rdone b-4-rv-1 1; rdone b-4-rv-2 1
  watch_once
  next_round
  assert_output --partial "review: b-4-rv-1, b-4-rv-2 round 2 of b-4"
  assert_contains_all "$(cat "$TASKS/b-4-rv-2/inbox/001.msg")" "Pinned SHA: $(git -C "$CHIEF_HOME/worktrees/b-4" rev-parse HEAD)"
  watch_silent
  rdone b-4-rv-1 2; rdone b-4-rv-2 2
  watch_once
  assert_output --partial "state: done · round 2"
  watch_silent
}

@test "watch: a failed reviewer wakes Chief at once and does not hold its sibling back" {
  round_one
  wait_settled b-4-rv-1; wait_settled b-4-rv-2
  echo "failed: could not run checks" >> "$TASKS/b-4-rv-1/status"
  watch_once
  assert_output --partial "b-4-rv-1: state: failed"
  rdone b-4-rv-2 1
  watch_once
  assert_output --partial "b-4-rv-2: state: done"
}

@test "watch: a torn-down reviewer is skipped" {
  round_one
  timeout 90 "$BIN/chief-teardown.sh" b-4-rv-1 --abandon >/dev/null 2>&1
  rdone b-4-rv-2 1
  watch_once
  assert_output --partial "b-4-rv-2: state: done"
}

@test "round 2: a torn-down reviewer is dropped from the next round" {
  round_one
  timeout 90 "$BIN/chief-teardown.sh" b-4-rv-1 --abandon >/dev/null 2>&1
  next_round b-4-rv-2
  assert_output --partial "review: b-4-rv-2 round 2 of b-4"
}

@test "round 1: a spawn failure discards the reviewers started and links nothing" {
  chief_done_builder b-6
  standin_never_ready b-6-rv-2
  CHIEF_HERDR_START_WAIT=3 run "$RV" b-6
  assert_failure 1
  assert_equal "$(chief_meta_get b-6-rv-1 status):$(chief_meta_get b-6 reviewer 2>/dev/null || true)" "torn-down:"
}
