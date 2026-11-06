# chief-agents.sh: the effective agent per role, read-only.

setup() {
  load ../lib/common
  export CHIEF_HOME="$BATS_TEST_TMPDIR/.chief"
  mkdir -p "$CHIEF_HOME/config"
  CFG="$CHIEF_HOME/config/agents"
  AGENTS="$BIN/chief-agents.sh"
}

squeezed() { "$AGENTS" | tr -s ' '; }

@test "no config: prints one line per role with claude flagged as the default" {
  run squeezed
  assert_equal "${#lines[@]}" 4
  assert_output --partial "builder: claude (no pool configured)"
}

@test "pools: a role's own pool has no marker, the others show the global fallback" {
  printf 'claude:opus\n[builder]\ncodex:gpt-5\n[reviewer]\ncopilot\n' > "$CFG"
  run squeezed
  assert_output --partial "builder: codex:gpt-5"
  [[ $(grep '^builder' <<< "$output") != *fallback* ]]
  assert_output --partial "reviewer: copilot"
  assert_output --partial "researcher: claude:opus (global fallback)"
  assert_output --partial "brainstormer: claude:opus (global fallback)"
}

@test "round-robin: reads without moving the cursor" {
  printf 'strategy = round-robin\n[builder]\ncodex:gpt-5\nclaude:sonnet\n' > "$CFG"
  "$AGENTS" >/dev/null; "$AGENTS" >/dev/null
  run squeezed
  assert_output --partial "builder: codex:gpt-5"
  assert_not_exist "$CHIEF_HOME/state/agent-cursor-builder"
}

@test "weighted: lists the pool with its weights" {
  printf 'strategy = weighted\n[builder]\ncodex:gpt-5 weight=2\nclaude:sonnet\n' > "$CFG"
  run squeezed
  assert_output --partial "builder: weighted pool: codex:gpt-5 (2), claude:sonnet (1)"
}

@test "bad config: fails" {
  printf '[prod]\n' > "$CFG"
  run "$AGENTS"
  assert_failure 1
}
