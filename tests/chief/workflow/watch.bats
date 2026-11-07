# chief-watch.sh's in_flight_ids and notify-once rules, against a real herdr.
# Once a task's crew state reaches a terminal state and the normal flow
# (chief-backlog.sh hold) has acted on it, the watcher stops re-notifying about
# it on every Stop hook: in_flight_ids only follows tasks whose meta status is
# still "working".

setup() {
  load ../lib/common
  chief_common_setup
}

teardown() { chief_herdr_stop; }

@test "notify: a done task wakes once, then stays silent and leaves flight after hold" {
  chief_project
  chief_herdr_server
  "$BIN/chief-backlog.sh" add t-1 "Add hello.txt" >/dev/null
  chief_spawn_quiet t-1
  chief_commit_file t-1 hello.txt hello >/dev/null
  echo "done: added hello.txt" >> "$CHIEF_HOME/tasks/t-1/status"

  chief_watch_once
  assert_output --partial "t-1: state: done"
  chief_watch_silent

  "$BIN/chief-backlog.sh" hold t-1 "reported" >/dev/null
  chief_watch_once
  assert_output "nothing in flight"
}

@test "notify: a resumed task is not re-announced with the state Chief acted on" {
  chief_project
  chief_herdr_server
  "$BIN/chief-backlog.sh" add t-2 "Add world.txt" >/dev/null
  chief_spawn_quiet t-2
  echo "done: added world.txt" >> "$CHIEF_HOME/tasks/t-2/status"
  chief_watch_once
  assert_output --partial "t-2: state: done"

  "$BIN/chief-backlog.sh" hold t-2 "steering: try a different approach" >/dev/null
  "$BIN/chief-backlog.sh" status t-2 in-flight >/dev/null
  chief_watch_silent
  chief_watch_silent

  echo "done: switched to the new approach" >> "$CHIEF_HOME/tasks/t-2/status"
  chief_watch_once
  assert_output --partial "t-2: state: done · switched to the new approach"
  chief_watch_silent
}

@test "notify: a brainstormer waiting on the operator never wakes Chief, its done does" {
  chief_project
  chief_herdr_server
  chief_spawn_quiet bs-1 --mode brainstormer
  chief_wait_settled bs-1
  echo "working: brainstorming with operator" >> "$CHIEF_HOME/tasks/bs-1/status"
  turn_ago() { touch -d "@$(($(date +%s) - $1))" "$CHIEF_HOME/tasks/bs-1/turn-ended"; }
  chief_watch_silent
  turn_ago 3600
  chief_watch_silent
  turn_ago 1000000
  chief_watch_silent
  echo "done: spec ready" >> "$CHIEF_HOME/tasks/bs-1/status"
  chief_watch_once
  assert_output --partial "bs-1: state: done · spec ready"
}

@test "notify: the idle counter alone is not a state change" {
  chief_project
  chief_herdr_server
  chief_spawn_quiet st-1
  chief_wait_settled st-1
  echo "working: waiting on a job" >> "$CHIEF_HOME/tasks/st-1/status"
  stale_ago() { touch -d "@$(($(date +%s) - $1))" "$CHIEF_HOME/tasks/st-1/turn-ended"; }

  stale_ago 250
  chief_watch_once
  assert_output --partial "st-1: state: stale"
  stale_ago 400
  chief_watch_silent
  echo "working: back at it" >> "$CHIEF_HOME/tasks/st-1/status"
  touch "$CHIEF_HOME/tasks/st-1/turn-ended"
  chief_watch_silent
  stale_ago 250
  chief_watch_once
  assert_output --partial "st-1: state: stale"

  # activity that only touches turn-ended starts a new episode too
  touch "$CHIEF_HOME/tasks/st-1/turn-ended"
  chief_watch_silent
  stale_ago 260
  chief_watch_once
  assert_output --partial "st-1: state: stale"
  chief_watch_silent
}

@test "notify: a changed [agent: ...] tag is not a state change" {
  chief_project
  chief_herdr_server
  chief_spawn_quiet ag-1
  echo "done: shipped" >> "$CHIEF_HOME/tasks/ag-1/status"
  set_ag() {
    local m="$CHIEF_HOME/tasks/ag-1/meta"
    grep -vE '^(agent|model)=' "$m" > "$m.tmp"; mv "$m.tmp" "$m"
    printf 'agent=claude\nmodel=%s\n' "$1" >> "$m"
  }
  set_ag ""
  chief_watch_once
  assert_output --partial "ag-1: state: done"
  set_ag sonnet
  chief_watch_silent
  echo "done: shipped again" >> "$CHIEF_HOME/tasks/ag-1/status"
  chief_watch_once
  assert_output --partial "ag-1: state: done"
}

@test "notify: a trailing [reviewer: id] tag is not a state change" {
  chief_project
  chief_herdr_server
  chief_spawn_quiet rv-1
  echo "done: shipped" >> "$CHIEF_HOME/tasks/rv-1/status"
  chief_watch_once
  assert_output --partial "rv-1: state: done"
  printf 'reviewer=rv-1-review\n' >> "$CHIEF_HOME/tasks/rv-1/meta"
  chief_watch_silent

  local m="$CHIEF_HOME/tasks/rv-1/meta"
  grep -v '^notify-baseline=' "$m" > "$m.tmp"; mv "$m.tmp" "$m"
  printf 'notify-baseline=state: done · shipped [mode: builder] [agent: claude]\n' >> "$m"
  chief_watch_silent
}

@test "notify: keeps a literal \"[mode:\" in the detail" {
  chief_project
  chief_herdr_server
  chief_spawn_quiet lt-1
  echo "done: fixed [mode: x] parser" >> "$CHIEF_HOME/tasks/lt-1/status"
  chief_watch_once
  assert_output --partial "lt-1: state: done"
  chief_watch_silent
  printf 'reviewer=lt-1-review\n' >> "$CHIEF_HOME/tasks/lt-1/meta"
  chief_watch_silent
  echo "done: fixed [mode: x] parser, round 2" >> "$CHIEF_HOME/tasks/lt-1/status"
  chief_watch_once
  assert_output --partial "round 2"
}

# --- single instance: the newest watcher owns the home ---

line() { echo "t-2: state: done · $1 [mode: builder] [agent: claude]"; }
owner_is_not() { [ -s "$CHIEF_HOME/state/watch.owner" ] && [ "$(cat "$CHIEF_HOME/state/watch.owner")" != "$1" ]; }

# bg_watch <out> <watcher> - a background watcher; its exit code lands in <out>
# and its pid in BG_PIDS. Wait for those, not a bare `wait`: bats' timeout
# watchdog is a child of the test too.
BG_PIDS=()
bg_watch() { ( rc=0; CHIEF_POLL=1 timeout 10 "$2" > "$1" 2>&1 || rc=$?; echo "rc=$rc" >> "$1" ) 3>&- & BG_PIDS+=($!); }

@test "watcher: racing watchers deliver a change once" {
  chief_project
  chief_herdr_server
  chief_spawn_quiet t-2
  echo "done: race" >> "$CHIEF_HOME/tasks/t-2/status"
  for i in 1 2 3; do ( CHIEF_POLL=1 timeout 6 "$BIN/chief-watch.sh" > "$WORK/race-$i.out" 2>&1 ) 3>&- & BG_PIDS+=($!); done
  wait "${BG_PIDS[@]}"
  assert_equal "$(cat "$WORK"/race-*.out)" "$(line race)"
}

@test "watcher: an older one exits silently when a newer one arms through the hook" {
  chief_project
  chief_herdr_server
  chief_spawn_quiet t-2
  echo "working: older exits" >> "$CHIEF_HOME/tasks/t-2/status"
  export CLAUDE_PROJECT_DIR="$WORK/project"
  bg_watch "$WORK/old.out" "$BIN/chief-watch.sh"
  eventually 10 owner_is_not ""
  old_owner=$(cat "$CHIEF_HOME/state/watch.owner")
  bg_watch "$WORK/new.out" "$REPO_ROOT/plugins/chief/hooks/stop-watch-arm.sh"
  eventually 10 owner_is_not "$old_owner"
  echo "done: older exits" >> "$CHIEF_HOME/tasks/t-2/status"
  wait "${BG_PIDS[@]}"
  assert_equal "$(cat "$WORK/old.out")" "rc=0"
  assert_equal "$(cat "$WORK/new.out")" "chief watcher: $(line 'older exits')
$(cat "$REPO_ROOT/plugins/chief/hooks/wake-reply.txt")
rc=2"
}

@test "watcher: a displaced one that read an older state leaves the baseline alone" {
  chief_project
  chief_herdr_server
  chief_spawn_quiet t-2
  echo "working: gated" >> "$CHIEF_HOME/tasks/t-2/status"
  cp -r "$REPO_ROOT/plugins/chief" "$WORK/plugin-copy"
  cat > "$WORK/plugin-copy/bin/task/chief-crew-state.sh" <<GATE
#!/usr/bin/env bash
touch "$WORK/gate-entered"
while [ ! -e "$WORK/gate-release" ]; do sleep 0.1; done
echo "state: working"
GATE
  bg_watch "$WORK/gated.out" "$WORK/plugin-copy/bin/chief-watch.sh"
  eventually 10 test -e "$WORK/gate-entered"
  echo "done: gated" >> "$CHIEF_HOME/tasks/t-2/status"
  run env CHIEF_POLL=1 timeout 10 "$BIN/chief-watch.sh"
  assert_output "$(line gated)"
  touch "$WORK/gate-release"
  wait "${BG_PIDS[@]}"
  assert_equal "$(cat "$WORK/gated.out")" "rc=0"
}
