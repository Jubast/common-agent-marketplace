# chief-backlog.sh: the whole markdown-file backlog. No backend involved.

setup() {
  load ../lib/common
  cd "$BATS_TEST_TMPDIR" && git init -q
  export CHIEF_HOME="$BATS_TEST_TMPDIR/.chief"
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
  BL="$BIN/chief-backlog.sh"
  BACKLOG="$CHIEF_HOME/backlog.md"
}

@test "add: files a queued record that list and next see" {
  run "$BL" add t-1 "Add rate limiting"; assert_success
  run "$BL" add t-2 "Fix flaky test"; assert_success
  run "$BL" list
  assert_output --partial "## t-1 [queued] Add rate limiting"
  assert_equal "$("$BL" next)" t-1
}

@test "status: moves a record to in-flight and next skips it" {
  "$BL" add t-1 "a"; "$BL" add t-2 "b"
  run "$BL" status t-1 in-flight; assert_success
  run "$BL" show t-1
  assert_output --partial "[in-flight]"
  assert_equal "$("$BL" next)" t-2
}

@test "hold: sets status and note and leaves a task without meta alone" {
  "$BL" add t-1 "a"
  run "$BL" hold t-1 "blocked on the operator - which limiter lib?"; assert_success
  run "$BL" show t-1
  assert_output --partial "[held]"
  assert_output --partial "note: blocked on the operator"
  assert_equal "$(chief_meta_get t-1 status 2>/dev/null || true)" ""
}

@test "note: overwrites the existing note" {
  "$BL" add t-1 "a"; "$BL" hold t-1 "blocked on the operator - which limiter lib?"
  run "$BL" note t-1 "operator said: token-bucket"; assert_success
  run cat "$BACKLOG"
  assert_output --partial "note: operator said: token-bucket"
  refute_output --partial "blocked on the operator"
  assert_equal "$(grep -c '^note:' "$BACKLOG")" 1
}

@test "done: marks the record done and next finds nothing queued" {
  "$BL" add t-2 "b"
  run "$BL" done t-2; assert_success
  run "$BL" list done
  assert_output --partial "t-2"
  assert_equal "$("$BL" next)" ""
}

@test "hold, done: move a spawned task's meta status off working" {
  "$BL" add t-3 "c"; chief_meta_set t-3 status working
  run "$BL" hold t-3 "needs a decision"; assert_success
  assert_equal "$(chief_meta_get t-3 status)" held
  "$BL" add t-4 "d"; chief_meta_set t-4 status working
  run "$BL" done t-4; assert_success
  assert_equal "$(chief_meta_get t-4 status)" done
}

@test "status: in-flight un-holds a task and restores meta working (#31)" {
  "$BL" add t-5 "e"; chief_meta_set t-5 status working
  "$BL" hold t-5 "needs a decision"
  assert_equal "$(chief_meta_get t-5 status)" held
  run "$BL" status t-5 in-flight; assert_success
  run "$BL" show t-5
  assert_output --partial "[in-flight]"
  assert_equal "$(chief_meta_get t-5 status)" working
}

@test "agent tag: only in-flight records carry it, after the title" {
  "$BL" add t-5 "Fifth task"; "$BL" status t-5 in-flight
  "$BL" add t-6 "Sixth task"
  chief_meta_set t-6 agent codex; chief_meta_set t-6 model gpt-5
  run "$BL" show t-6
  refute_output --partial "[agent:"
  "$BL" status t-6 in-flight
  run "$BL" show t-6
  assert_output --partial "## t-6 [in-flight] Sixth task [agent: codex:gpt-5]"
  run "$BL" list in-flight
  assert_output --partial "## t-6 [in-flight] Sixth task [agent: codex:gpt-5]"
  run "$BL" list
  assert_output --partial "## t-5 [in-flight] Fifth task"
  assert_equal "$("$BL" next)" ""
}

@test "status: in-flight creates no meta for a task without one" {
  "$BL" add t-2 "b"
  run "$BL" status t-2 in-flight; assert_success
  assert_equal "$(chief_meta_get t-2 status 2>/dev/null || true)" ""
}

@test "add: refuses a duplicate id" {
  "$BL" add t-1 "a"
  run -1 "$BL" add t-1 "dup"
}

@test "add: refuses an invalid id, suggests a valid one and writes nothing" {
  LONG=build-keycloak-name-with-a-long-tail-of-words
  run -1 "$BL" add "$LONG" t
  assert_output --partial "try 'build-keycloak-name-with-a-long'"
  run cat "$BACKLOG"
  refute_output --partial "$LONG"
}

@test "long id: status, note and done still work on one already filed" {
  LONG=build-keycloak-name-with-a-long-tail-of-words
  mkdir -p "$CHIEF_HOME"
  printf '## %s [queued] old long id\n' "$LONG" >> "$BACKLOG"
  run "$BL" status "$LONG" in-flight; assert_success
  run "$BL" note "$LONG" "n"; assert_success
  run "$BL" done "$LONG"; assert_success
}

@test "unknown id: status and note are refused, show prints nothing" {
  "$BL" add t-1 "a"
  run -1 "$BL" status nope queued
  run -1 "$BL" status t-1 bogus
  run -1 "$BL" note nope "x"
  assert_equal "$("$BL" show nope)" ""
}

# backlog_task_meta <id> <endpoint> - a hand-written meta for a spawned task
backlog_task_meta() {
  mkdir -p "$CHIEF_HOME/tasks/$1"
  printf 'project=%s\nmode=builder\nbranch=feat/%s\nworktree=%s/worktrees/%s\nendpoint=%s\n' \
    "$BATS_TEST_TMPDIR" "$1" "$CHIEF_HOME" "$1" "$2" > "$CHIEF_HOME/tasks/$1/meta"
}

@test "show: prints the branch, worktree, report path and workspace of a spawned task" {
  backlog_task_meta t-1 herdr:w3:p1
  "$BL" add t-1 "Task one" >/dev/null
  "$BL" status t-1 in-flight >/dev/null
  run "$BL" show t-1
  assert_output --partial "  branch: feat/t-1"
  assert_output --partial "  worktree: $CHIEF_HOME/worktrees/t-1"
  assert_output --partial "  report: $CHIEF_HOME/tasks/t-1/report.md"
  assert_output --partial "  workspace: t-1"
}

@test "show: names the workspace of an Orca or hc task from its endpoint" {
  for e in orca:h hc:t3; do
    backlog_task_meta "old-${e%%:*}" "$e"
    "$BL" add "old-${e%%:*}" "Task" >/dev/null
    run "$BL" show "old-${e%%:*}"
    assert_output --partial "  workspace: old-${e%%:*}"
  done
}
