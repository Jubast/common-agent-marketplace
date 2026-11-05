# chief-backlog.sh: the whole markdown-file backlog. No backend involved.

setup() {
  load ../lib/common
  cd "$BATS_TEST_TMPDIR" && git init -q
  export CHIEF_HOME="$BATS_TEST_TMPDIR/.chief"
  . "$CHIEF_BIN/lib/paths.sh"
  . "$CHIEF_BIN/lib/meta.sh"
  BL="$CHIEF_BIN/chief-backlog.sh"
  BACKLOG="$CHIEF_HOME/backlog.md"
}

@test "add files queued records; list and next see them" {
  run "$BL" add t-1 "Add rate limiting"; assert_success
  run "$BL" add t-2 "Fix flaky test"; assert_success
  run "$BL" list
  assert_output --partial "## t-1 [queued] Add rate limiting"
  assert_equal "$("$BL" next)" t-1
}

@test "status moves a record to in-flight and next skips it" {
  "$BL" add t-1 "a"; "$BL" add t-2 "b"
  run "$BL" status t-1 in-flight; assert_success
  run "$BL" show t-1
  assert_output --partial "[in-flight]"
  assert_equal "$("$BL" next)" t-2
}

@test "hold sets status and note together, and is a no-op on meta without a meta record" {
  "$BL" add t-1 "a"
  run "$BL" hold t-1 "blocked on the operator - which limiter lib?"; assert_success
  run "$BL" show t-1
  assert_output --partial "[held]"
  assert_output --partial "note: blocked on the operator"
  assert_equal "$(chief_meta_get t-1 status 2>/dev/null || true)" ""
}

@test "note overwrites the existing note, not appends" {
  "$BL" add t-1 "a"; "$BL" hold t-1 "blocked on the operator - which limiter lib?"
  run "$BL" note t-1 "operator said: token-bucket"; assert_success
  run cat "$BACKLOG"
  assert_output --partial "note: operator said: token-bucket"
  refute_output --partial "blocked on the operator"
  assert_equal "$(grep -c '^note:' "$BACKLOG")" 1
}

@test "done marks a record done; next returns nothing once none is queued" {
  "$BL" add t-2 "b"
  run "$BL" done t-2; assert_success
  run "$BL" list done
  assert_output --partial "t-2"
  assert_equal "$("$BL" next)" ""
}

@test "hold and done on a spawned task advance its meta status away from working" {
  "$BL" add t-3 "c"; chief_meta_set t-3 status working
  run "$BL" hold t-3 "needs a decision"; assert_success
  assert_equal "$(chief_meta_get t-3 status)" held
  "$BL" add t-4 "d"; chief_meta_set t-4 status working
  run "$BL" done t-4; assert_success
  assert_equal "$(chief_meta_get t-4 status)" done
}

@test "status in-flight un-holds a task and restores meta working, so the watcher picks it up again (#31)" {
  "$BL" add t-5 "e"; chief_meta_set t-5 status working
  "$BL" hold t-5 "needs a decision"
  assert_equal "$(chief_meta_get t-5 status)" held
  run "$BL" status t-5 in-flight; assert_success
  run "$BL" show t-5
  assert_output --partial "[in-flight]"
  assert_equal "$(chief_meta_get t-5 status)" working
}

@test "an in-flight record appends its agent after the title; queued ones carry none" {
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

@test "status in-flight creates no meta for a task without one" {
  "$BL" add t-2 "b"
  run "$BL" status t-2 in-flight; assert_success
  assert_equal "$(chief_meta_get t-2 status 2>/dev/null || true)" ""
}

@test "add refuses a duplicate id and invalid ids, suggests a valid one, writes nothing" {
  "$BL" add t-1 "a"
  run "$BL" add t-1 "dup"; assert_failure
  LONG=build-keycloak-name-with-a-long-tail-of-words
  for bad in "$LONG" Build-x build.x build_x "build x" 9lives; do
    run "$BL" add "$bad" "t"
    assert_failure
  done
  run "$BL" add "$LONG" t
  assert_output --partial "try 'build-keycloak-name-with-a-long'"
  run cat "$BACKLOG"
  refute_output --partial "$LONG"
}

@test "status, note and done still work on an already-filed long id" {
  LONG=build-keycloak-name-with-a-long-tail-of-words
  mkdir -p "$CHIEF_HOME"
  printf '## %s [queued] old long id\n' "$LONG" >> "$BACKLOG"
  run "$BL" status "$LONG" in-flight; assert_success
  run "$BL" note "$LONG" "n"; assert_success
  run "$BL" done "$LONG"; assert_success
}

@test "unknown ids and invalid status values are refused; show on an unknown id prints nothing" {
  "$BL" add t-1 "a"
  run "$BL" status nope queued; assert_failure
  run "$BL" status t-1 bogus; assert_failure
  run "$BL" note nope "x"; assert_failure
  assert_equal "$("$BL" show nope)" ""
}
