# agents/agent.sh: the .chief/config/agents file and its strategies.

setup() {
  load lib/common
  export CHIEF_HOME="$BATS_TEST_TMPDIR/.chief"
  . "$CHIEF_BIN/lib/paths.sh"
  chief_ensure_dirs
  . "$CHIEF_BIN/lib/agents/agent.sh"
  CFG="$CONFIG/agents"
}

# pick <mode> -> "agent:model|command" of the selection (current shell, so cursors persist)
pick() { chief_agent_select "$1" && echo "$SEL_AGENT:$SEL_MODEL|$SEL_COMMAND"; }
cfg() { cat > "$CFG"; }
w() { CHIEF_AGENT_RANDOM=$1 pick builder; }
rows() { printf '%s\n' "$@"; }
no_cursors() { rm -f "$STATE"/agent-cursor-*; }

@test "no config, or a config with no pool: claude, default model" {
  assert_equal "$(pick builder)" "claude:|"
  cfg <<< "# only comments"
  assert_equal "$(pick builder)" "claude:|"
}

@test "first: the first entry (strategy omitted), always the same" {
  cfg <<'EOF2'
# the pool

claude:opus
codex:gpt-5   # trailing comment
EOF2
  assert_equal "$(pick builder)" "claude:opus|"
  assert_equal "$(pick builder)" "claude:opus|"
}

@test "round-robin: rotates and wraps, persists its cursor, one cursor per mode" {
  cfg <<'EOF2'
strategy = round-robin   # rotate
claude:opus
codex:gpt-5
copilot
EOF2
  assert_equal "$(pick builder; pick builder; pick builder; pick builder)" \
    "$(rows "claude:opus|" "codex:gpt-5|" "copilot:|" "claude:opus|")"
  assert_equal "$(cat "$STATE/agent-cursor-builder")" 4
  assert_equal "$(pick researcher)" "claude:opus|"
  printf 'junk' > "$STATE/agent-cursor-builder"
  assert_equal "$(pick builder)" "claude:opus|"
}

@test "round-robin: parallel spawns never pick the same entry twice in a row" {
  cfg <<'EOF2'
strategy = round-robin
claude:opus
codex:gpt-5
copilot
EOF2
  for i in 1 2 3 4 5 6; do (chief_agent_select builder; echo "$SEL_AGENT:$SEL_MODEL") 3>&- & done > "$BATS_TEST_TMPDIR/par.out"
  wait
  assert_equal "$(sort "$BATS_TEST_TMPDIR/par.out" | uniq -c | awk '{print $1}' | tr '\n' ' ')" "2 2 2 "
}

@test "weighted: the injected random walks the weight ranges; weight=0 is never picked; all zero errors" {
  cfg <<'EOF2'
strategy = weighted
claude:opus   weight=3
codex:gpt-5   weight=2
copilot       weight=1
EOF2
  assert_equal "$(w 0; w 2; w 3; w 4; w 5; w 6)" \
    "$(rows "claude:opus|" "claude:opus|" "codex:gpt-5|" "codex:gpt-5|" "copilot:|" "claude:opus|")"
  cfg <<'EOF2'
strategy = weighted
claude weight=0
codex
EOF2
  assert_equal "$(w 0; w 7)" "$(rows "codex:|" "codex:|")"
  cfg <<'EOF2'
strategy = weighted
claude weight=0
EOF2
  run pick builder
  assert_output --partial "every weight in the pool is 0"
}

@test "random: equal weights, ignoring weight=" {
  cfg <<'EOF2'
strategy = random
claude weight=100
codex
EOF2
  assert_equal "$(w 0; w 1; w 2)" "$(rows "claude:|" "codex:|" "claude:|")"
}

@test "sections: a researcher pool with its own strategy; a builder pool inherits the global one" {
  cfg <<'EOF2'
strategy = first
claude:opus
[researcher]
strategy = round-robin
claude:haiku
codex:gpt-5-mini
[builder]
codex:gpt-5
EOF2
  assert_equal "$(pick researcher; pick researcher)" "$(rows "claude:haiku|" "codex:gpt-5-mini|")"
  assert_equal "$(pick builder)" "codex:gpt-5|"
}

@test "sections: a mode without a section uses the global pool; the researcher pool wins" {
  cfg <<'EOF2'
strategy = round-robin
claude:opus
[researcher]
codex
EOF2
  assert_equal "$(pick builder; pick builder)" "$(rows "claude:opus|" "claude:opus|")"
  assert_equal "$(pick researcher)" "codex:|"
}

@test "args and command are parsed next to weight in any order, without leaking into the next pick" {
  cfg <<'EOF2'
claude:opus args="--verbose --add-dir /x" weight=2 command="wrap"
codex args="--search"
EOF2
  chief_agent_select builder
  assert_equal "$SEL_AGENT|$SEL_ARGS|$SEL_COMMAND" "claude|--verbose --add-dir /x|wrap"
  cfg <<'EOF2'
strategy = round-robin
claude:opus
codex:gpt-5 args="--search"
EOF2
  chief_agent_select builder; chief_agent_select builder
  assert_equal "$SEL_AGENT|$SEL_ARGS" "codex|--search"
  cfg <<'EOF2'
claude:opus command="/opt/bin/claude --dangerously-skip-permissions --foo" weight=2
EOF2
  assert_equal "$(pick builder)" "claude:opus|/opt/bin/claude --dangerously-skip-permissions --foo"
}

@test "builder-only, researcher-only, both and neither pools" {
  cfg <<'EOF2'
claude:opus
[builder]
codex:gpt-5
EOF2
  assert_equal "$(pick builder; pick researcher)" "$(rows "codex:gpt-5|" "claude:opus|")"
  cfg <<'EOF2'
claude:opus
[researcher]
copilot
EOF2
  assert_equal "$(pick builder; pick researcher)" "$(rows "claude:opus|" "copilot:|")"
  cfg <<'EOF2'
[builder]
codex:gpt-5
[researcher]
copilot
EOF2
  assert_equal "$(pick builder; pick researcher)" "$(rows "codex:gpt-5|" "copilot:|")"
  cfg <<'EOF2'
claude:opus
EOF2
  assert_equal "$(pick builder; pick researcher)" "$(rows "claude:opus|" "claude:opus|")"
}

@test "peek: shows the next pick without advancing or writing a cursor" {
  cfg <<'EOF2'
strategy = round-robin
claude:opus
codex:gpt-5
EOF2
  chief_agent_select builder peek
  assert_equal "$SEL_AGENT $POOL_SRC" "claude global"
  chief_agent_select builder peek
  assert_equal "$SEL_AGENT" claude
  assert_not_exist "$STATE/agent-cursor-builder"
  chief_agent_select builder; chief_agent_select builder peek
  assert_equal "$SEL_AGENT" codex
}

@test "peek and describe: weighted and all pools are listed, the claude default is marked" {
  cfg <<'EOF2'
strategy = weighted
claude:opus weight=3
codex
[reviewer]
copilot
EOF2
  chief_agent_select builder peek
  assert_equal "$(chief_agent_describe)" "weighted pool: claude:opus (3), codex (1) (global fallback)"
  chief_agent_select reviewer peek
  assert_equal "$(chief_agent_describe)" "weighted pool: copilot (1)"
  cfg <<'EOF2'
[reviewer]
strategy = all
copilot
claude:sonnet args="--verbose"
EOF2
  assert_equal "$(chief_agent_count reviewer):$(chief_agent_count builder)" "2:1"
  CHIEF_AGENT_PICK=2 chief_agent_select reviewer
  assert_equal "$SEL_MODEL|$SEL_ARGS" "sonnet|--verbose"
  chief_agent_select reviewer peek
  assert_equal "$(chief_agent_describe)" "all pool: copilot, claude:sonnet"
  cfg <<< "# no pool"
  chief_agent_select builder peek
  assert_equal "$(chief_agent_describe)" "claude (no pool configured)"
}

@test "weights are decimal and bounded" {
  cfg <<'EOF2'
strategy = weighted
claude weight=08
codex weight=09
EOF2
  assert_equal "$(w 0; w 8; w 9; w 16; w 17)" "$(rows "claude:|" "codex:|" "codex:|" "codex:|" "claude:|")"
  cfg <<'EOF2'
strategy = weighted
claude weight=1000
codex
EOF2
  assert_equal "$(w 999; w 1000)" "$(rows "claude:|" "codex:|")"
}

@test "CRLF line endings are ignored" {
  printf 'strategy = round-robin\r\nclaude:opus\r\n[researcher]\r\ncodex args="--search"\r\n' > "$CFG"
  assert_equal "$(pick builder; pick researcher)" "$(rows "claude:opus|" "codex:|")"
}

# bad_config <content> [mode] - selects with that config, merging stderr
bad_config() { printf '%s\n' "$1" | cfg; chief_agent_select "${2:-builder}" 2>&1; }

config_error() {  # <config> <expected-fragment>
  run bad_config "$1"
  assert_output --partial "$2"
}
while IFS='|' read -r conf want; do
  bats_test_function --description "error: $want" -- config_error "$conf" "$want"
done <<'EOF2'
strategy = sometimes|unknown strategy 'sometimes'
[ship]|unknown section [ship]
[scout]|unknown section [scout]
[prod]|unknown section [prod]
Claude|bad profile 'Claude'
claude:opus weight=x|unexpected ' weight=x'
claude args="--x|unexpected
claude weight=99999999999|weight 99999999999 must be 0 to 1000
claude weight=1001|must be 0 to 1000
claude args="--x 'y'"|may only use letters
claude command="a; rm b"|command 'a; rm b' may only use
claude args="$(x)"|may only use
claude:opus color=red|unexpected ' color=red'
claude:op us|unexpected ' us'
claude command="unterminated|unexpected
claude:$(rm)|bad profile
EOF2

@test "error: names the file line" {
  run bad_config $'claude\ncodex x'
  assert_output --partial "agents:2:"
}

@test "sections: reviewer and brainstormer are valid" {
  run bad_config '[reviewer]'
  assert_output ""
  run bad_config '[brainstormer]'
  assert_output ""
}
