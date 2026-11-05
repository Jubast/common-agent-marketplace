# agents/agent.sh loader: per-task adapter from meta, command override, unknown agent.

setup() {
  load ../lib/common
  export CHIEF_HOME="$BATS_TEST_TMPDIR/.chief"
  . "$CHIEF_BIN/lib/paths.sh"
  chief_ensure_dirs
  . "$CHIEF_BIN/lib/meta.sh"
  . "$CHIEF_BIN/lib/agents/agent.sh"
}

@test "use: a task with no recorded agent is refused" {
  run chief_agent_use none
  assert_failure 1
}

@test "use: the model reaches the adapter; no model, no model flag" {
  chief_meta_set t1 agent claude
  chief_meta_set t1 model opus
  chief_agent_use t1
  assert_equal "$(chief_agent_command)" "claude --dangerously-skip-permissions --model opus"
  chief_meta_set t2 agent claude
  chief_meta_set t2 model ""
  chief_agent_use t2
  assert_equal "$(chief_agent_command)" "claude --dangerously-skip-permissions"
}

@test "command override replaces the launch command, and the next task does not inherit it" {
  chief_meta_set t1 agent claude
  chief_meta_set t1 model opus
  chief_meta_set t3 agent claude
  chief_meta_set t3 command "/opt/wrap/claude --foo --bar=1"
  chief_agent_use t3
  assert_equal "$(chief_agent_command)" "/opt/wrap/claude --foo --bar=1"
  chief_agent_use t1
  assert_equal "$(chief_agent_command)" "claude --dangerously-skip-permissions --model opus"
}

@test "args are appended after the unattended and model flags, and not inherited" {
  chief_meta_set t1 agent claude
  chief_meta_set t1 model opus
  chief_meta_set t5 agent claude
  chief_meta_set t5 model opus
  chief_meta_set t5 args "--verbose --add-dir /x"
  chief_agent_use t5
  assert_equal "$(chief_agent_command)" "claude --dangerously-skip-permissions --model opus --verbose --add-dir /x"
  chief_agent_use t1
  assert_equal "$(chief_agent_command)" "claude --dangerously-skip-permissions --model opus"
}

@test "load: an unknown agent lists the adapters" {
  chief_meta_set bad agent nope
  run chief_agent_use bad
  assert_output --partial "unknown agent 'nope' (available: claude"
}

@test "load: a name with a slash is refused" {
  chief_meta_set bad agent ../claude
  run chief_agent_use bad
  assert_output --partial "unknown agent '../claude'"
}

@test "load: the loader file is not an adapter" {
  chief_meta_set bad agent agent
  run chief_agent_use bad
  assert_output --partial "unknown agent 'agent'"
}

@test "list: only adapters" {
  assert_equal "$(chief_agent_list | paste -sd' ' -)" "claude codex copilot"
}
