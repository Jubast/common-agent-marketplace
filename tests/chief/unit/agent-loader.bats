# agents/agent.sh loader: per-task adapter from meta, the launch command of every
# adapter, command override, unknown agent.

setup() {
  load ../lib/common
  export CHIEF_HOME="$BATS_TEST_TMPDIR/.chief"
  . "$BIN/lib/paths.sh"
  chief_ensure_dirs
  . "$BIN/lib/meta.sh"
  . "$BIN/lib/agents/agent.sh"
}

@test "use: refuses a task with no recorded agent" {
  run chief_agent_use none
  assert_failure 1
}

# The launch command of each adapter with no model or args, a model, args, or both.
launch_command() {  # <agent> <model> <args> <expected>
  chief_meta_set t9 agent "$1"
  chief_meta_set t9 model "$2"
  chief_meta_set t9 args "$3"
  chief_agent_use t9
  assert_equal "$(chief_agent_command)" "$4"
}
for row in "claude|claude --dangerously-skip-permissions" \
           "codex|codex --dangerously-bypass-approvals-and-sandbox" \
           "copilot|copilot --allow-all"; do
  a=${row%%|*} base=${row#*|}
  bats_test_function --description "command: $a with no model or args" -- launch_command "$a" "" "" "$base"
  bats_test_function --description "command: $a with a model" -- launch_command "$a" big "" "$base --model big"
  bats_test_function --description "command: $a with args" -- launch_command "$a" "" "--search" "$base --search"
  bats_test_function --description "command: $a with a model and args" -- launch_command "$a" big "--search" "$base --model big --search"
done

@test "command: an override replaces the launch command and is not inherited" {
  chief_meta_set t1 agent claude
  chief_meta_set t1 model opus
  chief_meta_set t3 agent claude
  chief_meta_set t3 command "/opt/wrap/claude --foo --bar=1"
  chief_agent_use t3
  assert_equal "$(chief_agent_command)" "/opt/wrap/claude --foo --bar=1"
  chief_agent_use t1
  assert_equal "$(chief_agent_command)" "claude --dangerously-skip-permissions --model opus"
}

@test "args: appended after the unattended and model flags, not inherited" {
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

@test "load: refuses a name with a slash" {
  chief_meta_set bad agent ../claude
  run chief_agent_use bad
  assert_output --partial "unknown agent '../claude'"
}

@test "load: refuses the loader file itself" {
  chief_meta_set bad agent agent
  run chief_agent_use bad
  assert_output --partial "unknown agent 'agent'"
}

@test "list: names only the adapters" {
  assert_equal "$(chief_agent_list | paste -sd' ' -)" "claude codex copilot"
}
