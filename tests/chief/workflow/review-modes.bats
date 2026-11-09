# chief-review.sh run modes on a real herdr: [reviewer] mode, --mode, --only,
# and a sequential review that Chief drives one entry at a time.

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
}

teardown() { chief_herdr_stop; }

# pool [mode] - three entries (the first two on the same model); mode line if given
pool() {
  printf '[reviewer]\n%s\nclaude:opus\nclaude:opus args="--verbose"\nclaude:haiku\n' "${1:+mode = $1}" > "$CHIEF_HOME/config/agents"
}
rdone() { echo "done: round $2 $3 @x" >> "$TASKS/$1/status"; }  # <reviewer> <round> <PASS|FAIL>
# fix <builder> - the builder commits a fix and reports done again
fix() {
  local s; s=$(chief_commit_file "$1" "f$RANDOM.txt")
  echo "done: ${s:0:7} fixed" >> "$TASKS/$1/status"
}

@test "default mode is parallel: no strategy all means one reviewer" {
  pool
  chief_done_builder b-1
  run chief_review b-1
  assert_output --partial "review: b-1-rv round 1 of b-1"
  assert_equal "$(chief_meta_get b-1 reviewer):$(chief_meta_get b-1-rv pick)" "b-1-rv:0"
}

@test "mode = first: only pool entry 1 runs, under the id of its number" {
  pool first
  chief_done_builder b-1
  run chief_review b-1
  assert_output --partial "review: b-1-rv-1 round 1 of b-1"
  assert_equal "$(chief_meta_get b-1 reviewer):$(chief_meta_get b-1-rv-1 model)" "b-1-rv-1:opus"
}

@test "--mode overrides the configured mode" {
  pool first
  chief_done_builder b-1
  run chief_review b-1 --mode sequential --only 3
  assert_output --partial "review: b-1-rv-3 round 1 of b-1"
  assert_equal "$(chief_meta_get b-1-rv-3 model)" haiku
}

@test "--only: runs the chosen entries at once, each with its own entry's profile" {
  pool
  chief_done_builder b-1
  run chief_review b-1 --only 3,2
  assert_output --partial "review: b-1-rv-3, b-1-rv-2 round 1 of b-1"
  assert_equal "$(chief_meta_get b-1 reviewer)" "b-1-rv-3 b-1-rv-2"
  assert_equal "$(chief_meta_get b-1-rv-2 args)" "--verbose"
  assert_not_exist "$TASKS/b-1-rv-1/meta"
}

@test "ids: two same-model entries get distinct reviewers" {
  pool parallel
  chief_done_builder b-1
  run chief_review b-1 --only 1,2
  assert_output --partial "review: b-1-rv-1, b-1-rv-2 round 1"
  assert_equal "$(chief_meta_get b-1-rv-1 model):$(chief_meta_get b-1-rv-2 model)" "opus:opus"
  assert_equal "$(chief_meta_get b-1-rv-1 args):$(chief_meta_get b-1-rv-2 args)" ":--verbose"
}

@test "mode = ask: the script refuses it, --mode answers it" {
  pool ask
  chief_done_builder b-1
  run chief_review b-1
  assert_failure 1
  assert_output --partial "mode is ask"
  assert_not_exist "$TASKS/b-1-rv-1/meta"
  run chief_review b-1 --mode first
  assert_output --partial "review: b-1-rv-1 round 1"
}

@test "bad arguments are refused before anything starts" {
  pool
  chief_done_builder b-1
  for args in "--mode ask" "--mode all" "--mode first --only 1" "--mode sequential --only 1,2" "--only 4" "--only x" "--mode" "--bogus"; do
    run chief_review b-1 $args
    assert_failure 1
  done
  run chief_review b-1 --only 4
  assert_output --partial "not a reviewer pool entry (1-3)"
  assert_not_exist "$TASKS/b-1-rv-1/meta"
  assert_not_exist "$TASKS/b-1-rv/meta"
  printf '# no pool\n' > "$CHIEF_HOME/config/agents"
  run chief_review b-1 --only 1
  assert_output --partial "--only needs a pool"
}

@test "sequential: Chief runs one entry per call, the next on PASS" {
  pool sequential
  chief_done_builder b-1
  run chief_review b-1
  assert_output --partial "review: b-1-rv-1 round 1 of b-1"
  assert_output --partial "sequential: entry 1 of 3; on PASS run: chief-review.sh b-1 --mode sequential --only 2"
  assert_not_exist "$TASKS/b-1-rv-2/meta"
  chief_reviewer_working b-1-rv-1
  rdone b-1-rv-1 1 PASS
  chief_watch_once
  assert_output --partial "b-1-rv-1: state: done"
  run chief_review b-1 --mode sequential --only 2
  assert_output --partial "review: b-1-rv-2 round 1 of b-1"
  run chief_review b-1 --mode sequential --only 3
  assert_output --partial "sequential: entry 3 of 3, the last"
  assert_equal "$(chief_meta_get b-1 reviewer)" "b-1-rv-1 b-1-rv-2 b-1-rv-3"
}

@test "sequential: a stopped run leaves the later entries unstarted and the first FAIL wakes Chief" {
  pool sequential
  chief_done_builder b-1
  chief_review b-1 >/dev/null
  chief_reviewer_working b-1-rv-1
  printf 'Verdict: FAIL\n' > "$TASKS/b-1-rv-1/report.md"
  rdone b-1-rv-1 1 FAIL
  chief_watch_once
  assert_output --partial "b-1-rv-1: state: done"
  assert_not_exist "$TASKS/b-1-rv-2/meta"
}

@test "sequential, round 2: a new commit restarts at entry 1, the next entry continues the round" {
  pool sequential
  chief_done_builder b-1
  chief_review b-1 >/dev/null
  chief_review b-1 --only 2 >/dev/null
  printf 'Verdict: PASS\n' > "$TASKS/b-1-rv-1/report.md"; printf 'Verdict: FAIL\n' > "$TASKS/b-1-rv-2/report.md"
  rdone b-1-rv-1 1 PASS; rdone b-1-rv-2 1 FAIL
  "$BL" hold b-1 reported >/dev/null
  fix b-1
  run chief_review b-1
  assert_output --partial "review: b-1-rv-1 round 2 of b-1"
  assert_equal "$(chief_meta_get b-1-rv-1 armed | cut -d@ -f1):$(chief_meta_get b-1-rv-2 armed | cut -d@ -f1)" "2:1"
  assert_exist "$TASKS/b-1-rv-1/report.round-1.md"
  run chief_review b-1 --only 2
  assert_output --partial "review: b-1-rv-2 round 2 of b-1"
  assert_exist "$TASKS/b-1-rv-2/report.round-1.md"
  assert_contains_all "$(cat "$TASKS/b-1-rv-2/inbox/001.msg")" "Review round 2" "report.round-1.md"
  assert_equal "$(chief_meta_get b-1 review_round)" 2
}

@test "re-reviewing the same commit with an entry that finished is a new round" {
  pool first
  chief_done_builder b-1
  chief_review b-1 >/dev/null
  printf 'Verdict: PASS\n' > "$TASKS/b-1-rv-1/report.md"
  rdone b-1-rv-1 1 PASS
  run chief_review b-1
  assert_output --partial "review: b-1-rv-1 round 2 of b-1"
}

@test "an entry that is still reviewing the commit is refused, the others are not" {
  pool
  chief_done_builder b-1
  chief_review b-1 --only 1 >/dev/null
  chief_reviewer_working b-1-rv-1
  run chief_review b-1 --only 1
  assert_failure 1
  assert_output --partial "b-1-rv-1 is already reviewing"
  run chief_review b-1 --only 2
  assert_output --partial "review: b-1-rv-2 round 1 of b-1"
}

@test "a torn-down entry is skipped, and refused when it was the only one chosen" {
  pool
  chief_done_builder b-1
  chief_review b-1 --only 1,2 >/dev/null
  timeout 90 "$BIN/chief-teardown.sh" b-1-rv-1 --abandon >/dev/null 2>&1
  fix b-1
  run chief_review b-1 --only 1,2
  assert_output --partial "review: b-1-rv-2 round 2 of b-1"
  run chief_review b-1 --only 1
  assert_failure 1
  assert_output --partial "torn down: nothing to run"
}

@test "a spawn failure discards the entries this run started and keeps the earlier ones" {
  pool
  chief_done_builder b-1
  chief_review b-1 --only 1 >/dev/null
  standin_never_ready b-1-rv-3
  CHIEF_HERDR_START_WAIT=3 run "$RV" b-1 --only 2,3
  assert_failure 1
  assert_equal "$(chief_meta_get b-1-rv-2 status):$(chief_meta_get b-1 reviewer)" "torn-down:b-1-rv-1"
  assert_equal "$(chief_meta_get b-1-rv-1 status)" working
}

@test "a killed run leaves the entries it started linked and able to wake Chief" {
  pool
  chief_done_builder b-1
  standin_never_ready b-1-rv-2
  "$RV" b-1 --only 1,2 >/dev/null 2>&1 &
  RVPID=$!
  linked() { [ "$(chief_meta_get b-1 reviewer 2>/dev/null)" = b-1-rv-1 ]; }
  eventually 60 linked
  kill -9 "$RVPID"
  assert_equal "$(chief_meta_get b-1 reviewer)" b-1-rv-1
  chief_reviewer_working b-1-rv-1
  rdone b-1-rv-1 1 PASS
  chief_watch_once
  assert_output --partial "b-1-rv-1: state: done"
  rm "$STANDIN_DIR/modes/b-1-rv-2"
  run chief_review b-1 --only 1,2
  assert_output --partial "round 2"
}
