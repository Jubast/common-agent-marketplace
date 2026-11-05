# chief-spawn.sh's rollback-on-failure and spawn lock (issue #16, item 2), on a
# real herdr. The agent never rendering its TUI (the stand-in's never-ready mode)
# and a failing `herdr agent start` (a wrapper around the real herdr) both fail
# the spawn AFTER the worktree, branch and herdr workspace exist.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  chief_herdr_server
  export CHIEF_HERDR_START_WAIT=3
}

teardown() { chief_herdr_stop; }

STALLED='{"error":{"code":"agent_prompt_stalled","message":"agent prompt produced no observed working or blocked state within 5000 ms; current status is idle"}}'

assert_rolled_back() {  # <id>
  assert_not_exist "$CHIEF_HOME/worktrees/$1"
  assert_not_exist "$CHIEF_HOME/tasks/$1/meta"
  assert_not_exist "$CHIEF_HOME/tasks/$1/spawning"
  run git -C "$WORK/project" branch --list
  refute_output --partial "feat/$1"
  assert_equal "$(chief_trusted "$CHIEF_HOME/worktrees/$1")" unset
  assert_equal "$(grep -c "$1" "$CHIEF_HOME/state/trust-owned" 2>/dev/null || true)" 0
  run herdr workspace list
  refute_output --partial "\"$1\""
}

@test "rollback: an agent that never renders undoes worktree, branch, workspace, trust" {
  standin_never_ready t-fail
  run chief_spawn t-fail builder
  assert_failure 1
  assert_rolled_back t-fail
}

@test "rollback: a failing 'herdr agent start' undoes everything too" {
  chief_herdr_fault "agent start" 1000 before 1 '{"error":{"code":"internal","message":"boom"}}'
  run chief_spawn t-fail builder
  assert_failure 1
  assert_output --partial "'herdr agent start' failed for t-fail"
  assert_rolled_back t-fail
}

@test "rollback: malformed backend_spawn output after a real spawn is undone" {
  # a plugin copy whose herdr adapter drops the endpoint line of a real backend_spawn
  cp -r "$REPO_ROOT/plugins/chief" "$WORK/plugin-copy"
  cat >> "$WORK/plugin-copy/bin/lib/backends/herdr.sh" <<'PATCH'
eval "$(declare -f backend_spawn | sed '1s/backend_spawn/_real_backend_spawn/')"
backend_spawn() { _real_backend_spawn "$@" | head -n1; }
PATCH
  run "$WORK/plugin-copy/bin/chief-spawn.sh" t-malformed "$WORK/project" --mode builder --branch feat/t-malformed --intent x
  assert_failure 1
  assert_output --partial "backend_spawn returned malformed output"
  assert_rolled_back t-malformed
}

@test "interrupted spawn: reads blocked, wakes the watcher, tears down with --abandon" {
  mkdir -p "$CHIEF_HOME/tasks/t-stub"
  printf 'project=%s\nmode=builder\nbranch=chief/t-stub\nworktree=%s\nstatus=spawning\n' \
    "$WORK/project" "$CHIEF_HOME/worktrees/t-stub" > "$CHIEF_HOME/tasks/t-stub/meta"
  run "$BIN/task/chief-crew-state.sh" t-stub
  assert_output --partial "state: blocked"
  chief_watch_once
  assert_output --partial "t-stub: state: blocked"
  : > "$CHIEF_HOME/tasks/t-stub/spawning"
  run "$BIN/task/chief-crew-state.sh" t-stub
  assert_output --partial "state: working"   # the spawn lock is held: a live spawn
  rm -f "$CHIEF_HOME/tasks/t-stub/spawning"
  run timeout 90 "$BIN/chief-teardown.sh" t-stub --abandon
  assert_success
  run cat "$CHIEF_HOME/archive/t-stub/meta"
  assert_output --partial "status=torn-down"
}

@test "lock: refuses a same-id spawn while it is held and never reaches the backend" {
  mkdir -p "$CHIEF_HOME/state" "$CHIEF_HOME/tasks/t-locked"
  : > "$CHIEF_HOME/tasks/t-locked/spawning"
  run chief_spawn t-locked builder
  assert_failure 1
  assert_output --partial "already being spawned"
  assert_not_exist "$CHIEF_HOME/worktrees/t-locked"
  assert_not_exist "$CHIEF_HOME/tasks/t-locked/meta"
}

@test "lock: a successful spawn releases it" {
  run chief_spawn t-locked builder
  assert_success
  assert_not_exist "$CHIEF_HOME/tasks/t-locked/spawning"
}

# --- a first turn that never starts: one automatic retry, then a clean failure ---

@test "retry: a first turn that never starts is retried once and the spawn succeeds" {
  chief_herdr_fault "agent prompt" 2 before 1 "$STALLED"
  run chief_spawn t-retry builder
  assert_success
  assert_output --partial "spawned:"
  assert_exist "$CHIEF_HOME/tasks/t-retry/evidence/spawn-screen.1.txt"
  assert_equal "$(standin_turn_count t-retry)" 1
}

@test "retry: a second failed attempt rolls back and keeps each attempt's screen" {
  standin_mode t-retry drop=2
  run chief_spawn t-retry builder
  assert_failure 1
  assert_output --partial "no first turn started on either attempt"
  assert_rolled_back t-retry
  assert_exist "$CHIEF_HOME/tasks/t-retry/evidence/spawn-screen.1.txt"
  assert_exist "$CHIEF_HOME/tasks/t-retry/evidence/spawn-screen.2.txt"
}

@test "retry: a final failure drops the queued backlog record" {
  standin_mode t-q drop=2
  "$BIN/chief-backlog.sh" add t-q "queued" >/dev/null
  run chief_spawn t-q builder
  assert_failure 1
  assert_equal "$("$BIN/chief-backlog.sh" show t-q)" ""
}

@test "retry: a final failure leaves a live backlog record" {
  standin_mode t-live drop=2
  "$BIN/chief-backlog.sh" add t-live "live" >/dev/null
  "$BIN/chief-backlog.sh" status t-live in-flight >/dev/null
  run chief_spawn t-live builder
  assert_failure 1
  run "$BIN/chief-backlog.sh" show t-live
  assert_output --partial "[in-flight]"
}
