# agents/codex.sh and agents/copilot.sh: contract values, the CLI check and the
# screen texts. Launch commands are in agent-loader.bats; what herdr's agent
# process receives is in workflow/spawn-agents.bats.

setup() {
  load ../lib/common
  chief_common_setup  # the stand-in codex and copilot for agent_require
  export CHIEF_HOME="$BATS_TEST_TMPDIR/.chief"
  . "$BIN/lib/paths.sh"
  chief_ensure_dirs
  . "$BIN/lib/meta.sh"
  . "$BIN/lib/agents/agent.sh"
  for a in codex copilot; do chief_meta_set "n-$a" agent "$a"; done
}

adapter_contract() {
  local a=$1
  chief_agent_use "n-$a"
  assert_equal "$(agent_name)" "$a"  # what `herdr agent start --kind` receives
  run bash -c ". '$BIN/lib/agents/$a.sh'; agent_prepare /x && agent_release /x"
  assert_success
  assert_equal "$(agent_ready_text | wc -l | tr -d ' ')" 1
  assert_equal "$(agent_trust_text | wc -l | tr -d ' ')" 1
  assert_equal "$(agent_trust_keys)" ""
  assert_equal "$(PATH=/nonexistent agent_require 2>&1 || true)" "chief-agent: the '$a' CLI is not installed"
  run agent_require
  assert_success
}
for a in codex copilot; do
  bats_test_function --description "$a: contract has a no-op trust, ready and trust text, a CLI check" -- adapter_contract "$a"
done

screen_matches() { echo "$2" | grep -Eq "$($1)"; }

@test "codex: ready text matches the 0.164.0 status line and the old footer" {
  chief_agent_use n-codex
  screen_matches agent_ready_text '  ← for agents · ? for shortcuts'
  screen_matches agent_ready_text '100% context left'
}

@test "copilot: ready text matches the 1.0.97 footer and the older texts" {
  chief_agent_use n-copilot
  screen_matches agent_ready_text 'Interactive · Allow All'
  screen_matches agent_ready_text 'for commands'
  screen_matches agent_ready_text 'for shortcuts'
  screen_matches agent_paste_text '❯ [Paste #1 - 20 lines]'
}
