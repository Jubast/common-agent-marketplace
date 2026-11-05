# session-start.sh and stop-watch-arm.sh's own bash logic: what JSON/exit code
# they produce for a given .chief/ state. The hooks run as plain bash - no model
# tokens. Spawned tasks run on a real herdr with the stand-in.

setup() {
  load lib/common
  chief_common_setup
  SS="$REPO_ROOT/plugins/chief/hooks/session-start.sh"
  ARM="$REPO_ROOT/plugins/chief/hooks/stop-watch-arm.sh"
  unset CHIEF_HOME
}

teardown() { chief_herdr_stop; }

context() { jq -r '.hookSpecificOutput.additionalContext'; }

# configured_project - $WORK/configured/project with a herdr server and Chief set up
configured_project() {
  mkdir -p "$WORK/configured/project" && cd "$WORK/configured/project" && git init -q -b master
  git commit --allow-empty -q -m init
  export CHIEF_HOME="$WORK/configured/project/.chief" CHIEF_BACKEND=herdr
  chief_herdr_server
  "$BIN/chief-setup.sh" --backend orca >/dev/null
}
spawn_in() { timeout 90 "$BIN/chief-spawn.sh" "$1" "$WORK/configured/project" --mode "${2:-builder}" --branch "feat/$1" --intent "test" --spec "test" >/dev/null; }

@test "a fresh project: valid JSON identity, flagged as not configured; the arm hook lets the turn end" {
  mkdir -p "$WORK/fresh" && cd "$WORK/fresh" && git init -q
  run "$SS"
  assert_success
  echo "$output" | jq empty
  ctx=$(context <<< "$output")
  [[ $ctx == *"You are Chief"* && $ctx == *"NOT CONFIGURED YET"* && $ctx == *"'setup' skill"* ]]
  run "$ARM"
  assert_success
}

@test "a configured project reports its backend, no agents and an empty backlog" {
  configured_project
  ctx=$("$SS" | context)
  [[ $ctx == *"backend: orca"* && $ctx == *"agents: not configured, workers run claude"* && $ctx == *"(empty)"* ]]
  [[ $ctx != *"NOT CONFIGURED YET"* ]]
}

@test "in-flight tasks show status, mode, agent and a brainstormer's attach hint; the arm hook rewakes on a terminal state" {
  configured_project
  "$BIN/chief-backlog.sh" add t-1 "test task" >/dev/null
  spawn_in t-1
  echo "done: finished" >> "$CHIEF_HOME/tasks/t-1/status"
  ctx=$("$SS" | context)
  [[ $ctx == *"t-1: done: finished [mode: builder]"* && $ctx == *"[agent: claude]"* ]]

  spawn_in bs-1 brainstormer
  ctx=$("$SS" | context)
  [[ $ctx == *"[mode: brainstormer] [agent: claude] [attach: herdr workspace focus "* ]]
  [[ $ctx != *"[mode: builder] [agent: claude] [attach:"* ]]

  run "$ARM"
  assert_failure 2
  assert_output --partial "t-1"
}

@test "inside a builder's own worktree the hooks stand down" {
  configured_project
  spawn_in t-1
  echo "done: finished" >> "$CHIEF_HOME/tasks/t-1/status"
  cd "$CHIEF_HOME/worktrees/t-1"
  run "$SS"
  assert_output "{}"
  CLAUDE_PROJECT_DIR="$CHIEF_HOME/worktrees/t-1" run "$ARM"
  assert_success
  run "$ARM"   # no launch dir known: the cwd decides
  assert_success
}

@test "the primary session still arms after its cwd drifts into a worktree, resolving the home from the launch dir" {
  configured_project
  spawn_in t-2
  echo "done: finished" >> "$CHIEF_HOME/tasks/t-2/status"
  cd "$CHIEF_HOME/worktrees/t-2"
  CLAUDE_PROJECT_DIR="$WORK/configured/project" run "$ARM"
  assert_failure 2
  assert_output --partial "t-2"

  git -C "$WORK/configured/project" worktree add -q -b ext "$WORK/ext"
  spawn_in t-3
  echo "done: finished" >> "$CHIEF_HOME/tasks/t-3/status"
  cd "$WORK/ext"
  CHIEF_HOME= CLAUDE_PROJECT_DIR="$WORK/configured/project" run "$ARM"
  assert_output --partial "t-3"
}
