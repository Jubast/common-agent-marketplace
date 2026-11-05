# agents/codex.sh and agents/copilot.sh: contract values, model flag, CLI check.
# The last tests start Chief's claude adapter on a real herdr and check the args
# herdr's agent process receives (the stand-in records its argv).

setup() {
  load ../lib/common
  chief_common_setup
  export CHIEF_HOME="$BATS_TEST_TMPDIR/.chief"
  . "$CHIEF_BIN/lib/paths.sh"
  chief_ensure_dirs
  . "$CHIEF_BIN/lib/meta.sh"
  . "$CHIEF_BIN/lib/agents/agent.sh"
  for a in codex copilot; do
    chief_meta_set "n-$a" agent "$a"; chief_meta_set "m-$a" agent "$a"; chief_meta_set "m-$a" model big
  done
}

teardown() { chief_herdr_stop; }

@test "codex: herdr kind, no-approval flag, model flag only with a model" {
  chief_agent_use n-codex
  assert_equal "$(agent_name)" codex
  assert_equal "$(chief_agent_command)" "codex --dangerously-bypass-approvals-and-sandbox"
  chief_agent_use m-codex
  assert_equal "$(chief_agent_command)" "codex --dangerously-bypass-approvals-and-sandbox --model big"
}

@test "copilot: herdr kind, allow-all flag, model flag only with a model" {
  chief_agent_use n-copilot
  assert_equal "$(agent_name)" copilot
  assert_equal "$(chief_agent_command)" "copilot --allow-all"
  chief_agent_use m-copilot
  assert_equal "$(chief_agent_command)" "copilot --allow-all --model big"
}

adapter_contract() {
  local a=$1
  chief_agent_use "n-$a"
  run bash -c ". '$CHIEF_BIN/lib/agents/$a.sh'; agent_prepare /x && agent_release /x"
  assert_success
  assert_equal "$(agent_ready_text | wc -l | tr -d ' ')" 1
  assert_equal "$(agent_trust_text | wc -l | tr -d ' ')" 1
  assert_equal "$(agent_trust_keys)" ""
  assert_equal "$(PATH=/nonexistent agent_require 2>&1 || true)" "chief-agent: the '$a' CLI is not installed"
  run agent_require
  assert_success
}
for a in codex copilot; do
  bats_test_function --description "$a: trust is a no-op and never auto-accepted, ready/trust text, agent_require" -- adapter_contract "$a"
done

screen_matches() { echo "$2" | grep -Eq "$($1)"; }

@test "codex: ready text matches the 0.164.0 status line and the old footer" {
  chief_agent_use n-codex
  screen_matches agent_ready_text '  ← for agents · ? for shortcuts'
  screen_matches agent_ready_text '100% context left'
}

@test "copilot: ready text matches the 1.0.97 footer and the old texts; paste text the 1.0.95 placeholder" {
  chief_agent_use n-copilot
  screen_matches agent_ready_text 'Interactive · Allow All'
  screen_matches agent_ready_text 'for commands'
  screen_matches agent_ready_text 'for shortcuts'
  screen_matches agent_paste_text '❯ [Paste #1 - 20 lines]'
}

@test "a model and extra args reach the agent's own executable on herdr" {
  chief_project
  spawn t1 --agent claude:gpt-5 --args "--search"
  eventually 10 test -s "$STANDIN_DIR/t1.args"
  assert_equal "$(cat "$STANDIN_DIR/t1.args")" "--dangerously-skip-permissions --model gpt-5 --search"
}

@test "a command override supplies the args on herdr" {
  chief_project
  mkdir -p "$CHIEF_HOME/config"
  echo 'claude command="claude --allow-all --model other"' > "$CHIEF_HOME/config/agents"
  spawn t2
  eventually 10 test -s "$STANDIN_DIR/t2.args"
  assert_equal "$(cat "$STANDIN_DIR/t2.args")" "--allow-all --model other"
}

@test "a bare command override passes no arguments on herdr" {
  chief_project
  mkdir -p "$CHIEF_HOME/config"
  echo 'claude command="claude"' > "$CHIEF_HOME/config/agents"
  spawn t4
  eventually 10 test -e "$STANDIN_DIR/t4.args"
  assert_equal "$(cat "$STANDIN_DIR/t4.args")" ""
}

@test "extra args alone are appended to the launch command" {
  chief_meta_set y1 agent copilot; chief_meta_set y1 model m; chief_meta_set y1 args "--banner"
  chief_agent_use y1
  assert_equal "$(chief_agent_command)" "copilot --allow-all --model m --banner"
  chief_meta_set y2 agent codex; chief_meta_set y2 args "--search"
  chief_agent_use y2
  assert_equal "$(chief_agent_command)" "codex --dangerously-bypass-approvals-and-sandbox --search"
  chief_meta_set x1 agent codex; chief_meta_set x1 model gpt-5; chief_meta_set x1 args "--search"
  chief_agent_use x1
  assert_equal "$(chief_agent_command)" "codex --dangerously-bypass-approvals-and-sandbox --model gpt-5 --search"
}
