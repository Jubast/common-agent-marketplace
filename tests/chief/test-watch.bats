# chief-watch.sh's in_flight_ids and notify-once rules, against a real herdr.
# Once a task's crew state reaches a terminal state and the normal flow
# (chief-backlog.sh hold) has acted on it, the watcher stops re-notifying about
# it on every Stop hook: in_flight_ids only follows tasks whose meta status is
# still "working".

setup() {
  load lib/common
  chief_common_setup
}

teardown() { chief_herdr_stop; }

@test "a done task is surfaced once, then silent, then not in flight after hold" {
  chief_project
  "$BIN/chief-backlog.sh" add t-1 "Add hello.txt" >/dev/null
  spawn t-1
  ( cd "$CHIEF_HOME/worktrees/t-1" && echo hello > hello.txt && git add hello.txt \
      && git commit -q -m "add hello.txt" )
  echo "done: added hello.txt" >> "$CHIEF_HOME/tasks/t-1/status"

  watch_once
  assert_output --partial "t-1: state: done"
  watch_silent

  "$BIN/chief-backlog.sh" hold t-1 "reported" >/dev/null
  watch_once
  assert_output "nothing in flight"
}

@test "a resumed task is not re-nagged with the state Chief already acted on" {
  chief_project
  "$BIN/chief-backlog.sh" add t-2 "Add world.txt" >/dev/null
  spawn t-2
  echo "done: added world.txt" >> "$CHIEF_HOME/tasks/t-2/status"
  watch_once
  assert_output --partial "t-2: state: done"

  "$BIN/chief-backlog.sh" hold t-2 "steering: try a different approach" >/dev/null
  "$BIN/chief-backlog.sh" status t-2 in-flight >/dev/null
  watch_silent
  watch_silent

  echo "done: switched to the new approach" >> "$CHIEF_HOME/tasks/t-2/status"
  watch_once
  assert_output --partial "t-2: state: done · switched to the new approach"
  watch_silent
}

@test "brainstormer: an operator-wait never wakes Chief; done does" {
  chief_project
  spawn bs-1 --mode brainstormer
  wait_settled bs-1
  echo "working: brainstorming with operator" >> "$CHIEF_HOME/tasks/bs-1/status"
  turn_ago() { touch -d "@$(($(date +%s) - $1))" "$CHIEF_HOME/tasks/bs-1/turn-ended"; }
  watch_silent
  turn_ago 3600
  watch_silent
  turn_ago 1000000
  watch_silent
  echo "done: spec ready" >> "$CHIEF_HOME/tasks/bs-1/status"
  watch_once
  assert_output --partial "bs-1: state: done · spec ready"
}

@test "stale: the idle counter alone is not a state change" {
  chief_project
  spawn st-1
  wait_settled st-1
  echo "working: waiting on a job" >> "$CHIEF_HOME/tasks/st-1/status"
  stale_ago() { touch -d "@$(($(date +%s) - $1))" "$CHIEF_HOME/tasks/st-1/turn-ended"; }

  stale_ago 250
  watch_once
  assert_output --partial "st-1: state: stale"
  stale_ago 400
  watch_silent
  echo "working: back at it" >> "$CHIEF_HOME/tasks/st-1/status"
  touch "$CHIEF_HOME/tasks/st-1/turn-ended"
  watch_silent
  stale_ago 250
  watch_once
  assert_output --partial "st-1: state: stale"

  # activity that only touches turn-ended starts a new episode too
  touch "$CHIEF_HOME/tasks/st-1/turn-ended"
  watch_silent
  stale_ago 260
  watch_once
  assert_output --partial "st-1: state: stale"
  watch_silent
}

@test "agent flip: a changed [agent: ...] part is not a state change" {
  chief_project
  spawn ag-1
  echo "done: shipped" >> "$CHIEF_HOME/tasks/ag-1/status"
  set_ag() {
    local m="$CHIEF_HOME/tasks/ag-1/meta"
    grep -vE '^(agent|model)=' "$m" > "$m.tmp"; mv "$m.tmp" "$m"
    printf 'agent=claude\nmodel=%s\n' "$1" >> "$m"
  }
  set_ag ""
  watch_once
  assert_output --partial "ag-1: state: done"
  set_ag sonnet
  watch_silent
  echo "done: shipped again" >> "$CHIEF_HOME/tasks/ag-1/status"
  watch_once
  assert_output --partial "ag-1: state: done"
}

@test "reviewer tag: a trailing [reviewer: id] is not a state change, old-format baselines still match" {
  chief_project
  spawn rv-1
  echo "done: shipped" >> "$CHIEF_HOME/tasks/rv-1/status"
  watch_once
  assert_output --partial "rv-1: state: done"
  printf 'reviewer=rv-1-review\n' >> "$CHIEF_HOME/tasks/rv-1/meta"
  watch_silent

  local m="$CHIEF_HOME/tasks/rv-1/meta"
  grep -v '^notify-baseline=' "$m" > "$m.tmp"; mv "$m.tmp" "$m"
  printf 'notify-baseline=state: done · shipped [mode: builder] [agent: claude]\n' >> "$m"
  watch_silent
}

@test "a literal \" [mode: \" inside the detail is not a cut point" {
  chief_project
  spawn lt-1
  echo "done: fixed [mode: x] parser" >> "$CHIEF_HOME/tasks/lt-1/status"
  watch_once
  assert_output --partial "lt-1: state: done"
  watch_silent
  printf 'reviewer=lt-1-review\n' >> "$CHIEF_HOME/tasks/lt-1/meta"
  watch_silent
  echo "done: fixed [mode: x] parser, round 2" >> "$CHIEF_HOME/tasks/lt-1/status"
  watch_once
  assert_output --partial "round 2"
}

# --- single instance: the newest watcher owns the home ---

line() { echo "t-2: state: done · $1 [mode: builder] [agent: claude]"; }
owner_is_not() { [ -s "$CHIEF_HOME/state/watch.owner" ] && [ "$(cat "$CHIEF_HOME/state/watch.owner")" != "$1" ]; }

# bg_watch <out> <watcher> - a background watcher; its exit code lands in <out>
bg_watch() { ( rc=0; CHIEF_POLL=1 timeout 10 "$2" > "$1" 2>&1 || rc=$?; echo "rc=$rc" >> "$1" ) 3>&- & }

@test "racing watchers deliver the change once" {
  chief_project
  spawn t-2
  echo "done: race" >> "$CHIEF_HOME/tasks/t-2/status"
  for i in 1 2 3; do ( CHIEF_POLL=1 timeout 6 "$BIN/chief-watch.sh" > "$WORK/race-$i.out" 2>&1 ) 3>&- & done
  wait
  assert_equal "$(cat "$WORK"/race-*.out)" "$(line race)"
}

@test "an older watcher exits silently when a newer one arms through the hook" {
  chief_project
  spawn t-2
  echo "working: older exits" >> "$CHIEF_HOME/tasks/t-2/status"
  export CLAUDE_PROJECT_DIR="$WORK/project"
  bg_watch "$WORK/old.out" "$BIN/chief-watch.sh"
  eventually 10 owner_is_not ""
  old_owner=$(cat "$CHIEF_HOME/state/watch.owner")
  bg_watch "$WORK/new.out" "$REPO_ROOT/plugins/chief/hooks/stop-watch-arm.sh"
  eventually 10 owner_is_not "$old_owner"
  echo "done: older exits" >> "$CHIEF_HOME/tasks/t-2/status"
  wait
  assert_equal "$(cat "$WORK/old.out")" "rc=0"
  assert_equal "$(cat "$WORK/new.out")" "chief watcher: $(line 'older exits')
rc=2"
}

@test "a displaced watcher that read an older state exits without clearing the baseline" {
  chief_project
  spawn t-2
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
  wait
  assert_equal "$(cat "$WORK/gated.out")" "rc=0"
}

# chief_notify_line is idempotent
notify_line_idempotent() {
  . "$BIN/lib/meta.sh"
  local once twice
  once=$(chief_notify_line "$1"); twice=$(chief_notify_line "$once")
  assert_equal "$twice" "$once"
}
for x in "state: done · shipped" \
         "state: done · shipped [mode: builder]" \
         "state: done · shipped [mode: builder] [agent: claude] [reviewer: r-1]" \
         "state: stale · x, no turn activity for 250s [mode: builder] [for: a]" \
         "state: done · fixed [mode: x] parser [mode: builder] [agent: claude]" \
         ""; do
  bats_test_function --description "chief_notify_line is idempotent: '$x'" -- notify_line_idempotent "$x"
done

@test "chief_notify_line keeps a literal tag in the detail and cuts the real tags" {
  . "$BIN/lib/meta.sh"
  assert_equal "$(chief_notify_line "state: done · fixed [mode: x] parser [mode: builder] [agent: claude]")" \
    "state: done · fixed [mode: x] parser"
}
