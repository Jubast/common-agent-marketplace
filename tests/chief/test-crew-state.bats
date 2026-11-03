# chief-crew-state.sh's state classification on a real herdr. Most tasks have
# hand-written meta (isolating classification from the spawn machinery); one is
# really spawned, with the stand-in held `working`, for the busy/idle cases.

setup() {
  load lib/common
  chief_common_setup
  chief_project
  CS="$BIN/task/chief-crew-state.sh"
}

teardown() { chief_herdr_stop; }

# task_meta <id> <mode> [extra meta lines] - a hand-written task meta
task_meta() {
  local id=$1 mode=$2
  mkdir -p "$CHIEF_HOME/tasks/$id"
  printf 'project=%s\nmode=%s\nbranch=chief/%s\nworktree=%s/worktrees/%s\nendpoint=herdr:w9:p9\nstatus=working\n%s' \
    "$WORK/project" "$mode" "$id" "$CHIEF_HOME" "$id" "${3:-}" > "$CHIEF_HOME/tasks/$id/meta"
}
state() { run "$CS" "$1"; }
aged() { touch -d "@$(($(date +%s) - $2))" "$CHIEF_HOME/tasks/$1/turn-ended"; }

@test "refuses an unknown task id" {
  run "$CS" nope
  assert_failure
}

@test "a busy agent reads as working, an idle one by its turn-ended marker, mode and agent tags included" {
  standin_hold t-1
  spawn t-1
  state t-1
  assert_output --partial "state: working"
  assert_output --partial "[mode: builder]"
  chief_meta() { . "$BIN/lib/paths.sh"; . "$BIN/lib/meta.sh"; "$@"; }
  chief_meta chief_meta_set t-1 agent codex
  chief_meta chief_meta_set t-1 model gpt-5
  state t-1
  assert_output --partial "[mode: builder] [agent: codex:gpt-5]"

  standin_release t-1
  wait_settled t-1
  state t-1
  assert_output --partial "state: stale"          # idle, no turn-ended marker
  touch "$CHIEF_HOME/tasks/t-1/turn-ended"
  state t-1
  assert_output --partial "state: working"        # a fresh marker
  aged t-1 500
  state t-1
  assert_output --partial "state: stale"          # past the threshold
}

@test "status lines are authoritative regardless of liveness, and carry their detail" {
  task_meta t-1 builder
  echo "blocked: need operator input on limiter lib" >> "$CHIEF_HOME/tasks/t-1/status"
  state t-1; assert_output --partial "state: blocked · need operator input"
  echo "needs-decision: pick a library" >> "$CHIEF_HOME/tasks/t-1/status"
  state t-1; assert_output --partial "state: needs-decision"
  echo "failed: could not install deps" >> "$CHIEF_HOME/tasks/t-1/status"
  state t-1; assert_output --partial "state: failed"
  echo "done: added hello.txt" >> "$CHIEF_HOME/tasks/t-1/status"
  state t-1
  assert_output --partial "state: done · added hello.txt"
  assert_output --partial "[mode: builder]"
}

@test "a researcher task reports its own mode; an idle one is stale" {
  task_meta t-2 researcher
  echo "done: wrote report.md" >> "$CHIEF_HOME/tasks/t-2/status"
  state t-2; assert_output --partial "[mode: researcher]"
  task_meta t-3 researcher
  mkdir -p "$CHIEF_HOME/tasks/t-3"; aged t-3 500
  state t-3; assert_output --partial "state: stale"
}

@test "brainstormer: waiting on the operator in its pane is never stale" {
  task_meta bs-1 brainstormer $'attach=tail -f x.log\n'
  echo "working: brainstorming with operator" >> "$CHIEF_HOME/tasks/bs-1/status"
  state bs-1
  assert_output --partial "state: working · awaiting operator in pane"
  assert_output --partial "[mode: brainstormer]"
  assert_output --partial "[attach: tail -f x.log]"
  for age in 500 14500 1000000; do
    aged bs-1 "$age"
    state bs-1
    assert_output --partial "awaiting operator in pane"
  done

  echo "blocked: cannot read the repo" >> "$CHIEF_HOME/tasks/bs-1/status"
  state bs-1; assert_output --partial "state: blocked"
  echo "done: spec ready" >> "$CHIEF_HOME/tasks/bs-1/status"
  state bs-1
  assert_output --partial "state: done · spec ready"
  refute_output --partial "attach:"
  echo "failed: gave up" >> "$CHIEF_HOME/tasks/bs-1/status"
  state bs-1; assert_output --partial "state: failed"
}
