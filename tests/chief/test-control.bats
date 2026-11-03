# chief-control.sh: interrupt | exit | relaunch, against a real herdr.

setup() {
  load lib/common
  chief_common_setup
  chief_project
  CTL="$BIN/task/chief-control.sh"
}

teardown() { chief_herdr_stop; }

meta_of() { cat "$CHIEF_HOME/tasks/$1/meta"; }
alive() { kill -0 "$1" 2>/dev/null; }
dead() { ! alive "$1"; }
got_esc() { [ "$(standin_keys "$1")" = esc ]; }

@test "refuses an unknown task id" {
  run "$CTL" nope interrupt
  assert_failure
}

@test "refuses an unknown verb; interrupt delivers Escape and the agent keeps running" {
  spawn t-1
  wait_settled t-1
  run "$CTL" t-1 bogus
  assert_failure
  pid=$(cat "$STANDIN_DIR/t-1.pid")
  run "$CTL" t-1 interrupt
  assert_success
  eventually 10 got_esc t-1
  alive "$pid"
}

@test "exit stops the agent, keeps the worktree and records status=exited" {
  spawn t-1
  wait_settled t-1
  pid=$(cat "$STANDIN_DIR/t-1.pid")
  run "$CTL" t-1 exit
  assert_success
  eventually 10 dead "$pid"
  assert_exist "$CHIEF_HOME/worktrees/t-1"
  run meta_of t-1
  assert_output --partial "status=exited"
}

@test "relaunch needs --note, keeps the recorded agent, re-trusts and restarts in the same worktree" {
  spawn t-1 --agent claude:opus --args "--verbose"
  wait_settled t-1
  old_pid=$(cat "$STANDIN_DIR/t-1.pid")
  "$CTL" t-1 exit >/dev/null
  eventually 10 dead "$old_pid"

  run "$CTL" t-1 relaunch
  assert_failure

  mkdir -p "$CHIEF_HOME/config"; echo "codex:gpt-5" > "$CHIEF_HOME/config/agents"
  rm -f "$CLAUDE_CONFIG_DIR/.claude.json"
  run "$CTL" t-1 relaunch --note "was mid-way adding hello.txt"
  assert_success
  run meta_of t-1
  assert_output --partial "agent=claude"
  assert_output --partial "model=opus"
  assert_output --partial "args=--verbose"
  assert_output --partial "status=working"
  run tail -6 "$CHIEF_HOME/tasks/t-1/brief.md"
  assert_output --partial "was mid-way adding hello.txt"
  assert_output --partial "Relaunch checkpoint"
  new_pid=$(cat "$STANDIN_DIR/t-1.pid")
  assert_not_equal "$new_pid" "$old_pid"
  alive "$new_pid"
  assert_equal "$(jq -r --arg p "$CHIEF_HOME/worktrees/t-1" '.projects[$p].hasTrustDialogAccepted' "$CLAUDE_CONFIG_DIR/.claude.json")" true
}

@test "a relaunched brainstormer gets its attach hint recomputed; a builder records none" {
  spawn bs-1 --mode brainstormer
  spawn t-1
  sed -i '/^attach=/d' "$CHIEF_HOME/tasks/bs-1/meta"
  run "$CTL" bs-1 relaunch --note "mid-way"
  assert_success
  assert_output --partial "attach: herdr workspace focus"
  run meta_of bs-1
  assert_output --partial "attach=herdr workspace focus"
  "$CTL" t-1 relaunch --note "again" >/dev/null
  run meta_of t-1
  refute_output --partial "attach="
}
