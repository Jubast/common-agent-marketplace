# chief-agents.sh: the effective agent per role, read-only.

setup() {
  load ../lib/common
  export CHIEF_HOME="$BATS_TEST_TMPDIR/.chief"
  mkdir -p "$CHIEF_HOME/config"
  CFG="$CHIEF_HOME/config/agents"
  AGENTS="$BIN/chief-agents.sh"
}

squeezed() { "$AGENTS" | tr -s ' '; }

@test "no config: one line per role, claude default flagged" {
  run squeezed
  assert_equal "${#lines[@]}" 4
  assert_output --partial "builder: claude (no pool configured)"
}

@test "a role's own pool, its own marker-free line, and global fallbacks" {
  printf 'claude:opus\n[builder]\ncodex:gpt-5\n[reviewer]\ncopilot\n' > "$CFG"
  run squeezed
  assert_output --partial "builder: codex:gpt-5"
  [[ $(grep '^builder' <<< "$output") != *fallback* ]]
  assert_output --partial "reviewer: copilot"
  assert_output --partial "researcher: claude:opus (global fallback)"
  assert_output --partial "brainstormer: claude:opus (global fallback)"
}

@test "round-robin: read-only, the cursor does not move" {
  printf 'strategy = round-robin\n[builder]\ncodex:gpt-5\nclaude:sonnet\n' > "$CFG"
  "$AGENTS" >/dev/null; "$AGENTS" >/dev/null
  run squeezed
  assert_output --partial "builder: codex:gpt-5"
  assert_not_exist "$CHIEF_HOME/state/agent-cursor-builder"
}

@test "weighted: the pool is listed" {
  printf 'strategy = weighted\n[builder]\ncodex:gpt-5 weight=2\nclaude:sonnet\n' > "$CFG"
  run squeezed
  assert_output --partial "builder: weighted pool: codex:gpt-5 (2), claude:sonnet (1)"
}

@test "a bad config fails loudly" {
  printf '[prod]\n' > "$CFG"
  run "$AGENTS"
  assert_failure
}
