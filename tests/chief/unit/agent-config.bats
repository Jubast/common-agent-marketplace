# agents/agent.sh: the .chief/config/agents file and its strategies.

setup() {
  load ../lib/common
  export CHIEF_HOME="$BATS_TEST_TMPDIR/.chief"
  . "$BIN/lib/paths.sh"
  chief_ensure_dirs
  . "$BIN/lib/agents/agent.sh"
  CFG="$CONFIG/agents"
}

# pick <mode> -> "agent:model|command" of the selection (current shell, so cursors persist)
pick() { chief_agent_select "$1" && echo "$SEL_AGENT:$SEL_MODEL|$SEL_COMMAND"; }
cfg() { cat > "$CFG"; }
w() { CHIEF_AGENT_RANDOM=$1 pick builder; }
rows() { printf '%s\n' "$@"; }

@test "no pool: picks claude with the default model" {
  assert_equal "$(pick builder)" "claude:|"
  cfg <<< "# only comments"
  assert_equal "$(pick builder)" "claude:|"
}

@test "first: picks the first entry every time" {
  cfg <<'EOF2'
# the pool

claude:opus
codex:gpt-5   # trailing comment
EOF2
  assert_equal "$(pick builder)" "claude:opus|"
  assert_equal "$(pick builder)" "claude:opus|"
}

@test "round-robin: rotates, wraps and keeps one persisted cursor per mode" {
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

@test "round-robin: parallel spawns spread over the entries" {
  cfg <<'EOF2'
strategy = round-robin
claude:opus
codex:gpt-5
copilot
EOF2
  pids=()
  for i in 1 2 3 4 5 6; do (chief_agent_select builder; echo "$SEL_AGENT:$SEL_MODEL") 3>&- & pids+=($!); done > "$BATS_TEST_TMPDIR/par.out"
  wait "${pids[@]}"  # not a bare wait: bats' timeout watchdog is a child too
  assert_equal "$(sort "$BATS_TEST_TMPDIR/par.out" | uniq -c | awk '{print $1}' | tr '\n' ' ')" "2 2 2 "
}

@test "weighted: the random walks the ranges, weight=0 is skipped, all zero fails" {
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

@test "random: gives every entry an equal chance and ignores weight=" {
  cfg <<'EOF2'
strategy = random
claude weight=100
codex
EOF2
  assert_equal "$(w 0; w 1; w 2)" "$(rows "claude:|" "codex:|" "claude:|")"
}

@test "sections: a pool has its own strategy and the others inherit the global one" {
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

@test "parse: args and command sit next to weight in any order and do not leak" {
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

# pools_pick <config> <builder pick> <researcher pick>
pools_pick() {
  printf '%s\n' "$1" | cfg
  assert_equal "$(pick builder; pick researcher)" "$(rows "$2" "$3")"
}
bats_test_function --description "sections: a builder-only pool leaves the researcher on the global one" \
  -- pools_pick $'claude:opus\n[builder]\ncodex:gpt-5' "codex:gpt-5|" "claude:opus|"
bats_test_function --description "sections: a researcher-only pool leaves the builder on the global one" \
  -- pools_pick $'claude:opus\n[researcher]\ncopilot' "claude:opus|" "copilot:|"
bats_test_function --description "sections: both pools win over the global one" \
  -- pools_pick $'claude:opus\n[builder]\ncodex:gpt-5\n[researcher]\ncopilot' "codex:gpt-5|" "copilot:|"
bats_test_function --description "sections: a global pool alone serves both roles" \
  -- pools_pick 'claude:opus' "claude:opus|" "claude:opus|"
bats_test_function --description "sections: section pools alone serve their own roles" \
  -- pools_pick $'[builder]\ncodex:gpt-5\n[researcher]\ncopilot' "codex:gpt-5|" "copilot:|"

@test "peek: shows the next pick without moving or writing the cursor" {
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

@test "describe: lists weighted and all pools and marks the claude default" {
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
  assert_equal "$(chief_agent_pool_size reviewer):$(chief_agent_pool_size builder)" "2:0"
  CHIEF_AGENT_PICK=2 chief_agent_select reviewer
  assert_equal "$SEL_MODEL|$SEL_ARGS" "sonnet|--verbose"
  chief_agent_select reviewer peek
  assert_equal "$(chief_agent_describe)" "all pool: copilot, claude:sonnet"
  cfg <<< "# no pool"
  chief_agent_select builder peek
  assert_equal "$(chief_agent_describe)" "claude (no pool configured)"
}

@test "weight: is decimal and bounded" {
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

@test "parse: ignores CRLF line endings" {
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
  name=$(printf '%s' "$conf" | tr -c 'A-Za-z0-9 =:.[]_-' _)  # the name is eval'd by bats
  bats_test_function --description "config error: $name" -- config_error "$conf" "$want"
done <<'EOF2'
strategy = sometimes|unknown strategy 'sometimes'
[ship]|unknown section [ship]
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

@test "config error: names the file line" {
  run bad_config $'claude\ncodex x'
  assert_output --partial "agents:2:"
}

@test "sections: reviewer and brainstormer are valid" {
  run bad_config '[reviewer]'
  assert_output ""
  run bad_config '[brainstormer]'
  assert_output ""
}

@test "review mode: parallel by default, set in [reviewer] only, validated" {
  assert_equal "$(chief_agent_review_mode)" parallel
  cfg <<'EOF2'
[reviewer]
mode = sequential   # cheap first
claude
EOF2
  assert_equal "$(chief_agent_review_mode)" sequential
  for m in first ask parallel; do printf '[reviewer]\nmode=%s\nclaude\n' "$m" | cfg; assert_equal "$(chief_agent_review_mode)" "$m"; done
  printf '[reviewer]\nmode = all\n' | cfg
  run chief_agent_review_mode; assert_failure; assert_output --partial "unknown mode 'all'"
  printf 'mode = first\n' | cfg
  run chief_agent_review_mode; assert_failure; assert_output --partial "only for the [reviewer] section"
  printf '[builder]\nmode = first\n' | cfg
  run chief_agent_review_mode; assert_failure; assert_output --partial "only for the [reviewer] section"
}

@test "pick: CHIEF_AGENT_PICK selects that entry under any strategy" {
  cfg <<'EOF2'
strategy = round-robin
claude:opus
copilot:opus
codex
EOF2
  CHIEF_AGENT_PICK=2 chief_agent_select builder
  assert_equal "$SEL_AGENT:$SEL_MODEL" "copilot:opus"
  assert_not_exist "$STATE/agent-cursor-builder"
  CHIEF_AGENT_PICK=4 run chief_agent_select builder
  assert_failure; assert_output --partial "no pool entry 4"
}

@test "review picks: the entries a mode arms, narrowed by --only" {
  picks() { chief_agent_review_picks "$@" | paste -sd' ' -; }
  assert_equal "$(picks parallel)" "0"          # no pool
  cfg <<'EOF2'
[reviewer]
claude:haiku
copilot:haiku
codex
EOF2
  assert_equal "$(picks parallel):$(picks sequential):$(picks first)" "0:1:1"
  assert_equal "$(picks parallel 3,1,3):$(picks sequential 2)" "3 1:2"
  cfg <<'EOF2'
[reviewer]
strategy = all
claude:haiku
copilot:haiku
codex
EOF2
  assert_equal "$(picks parallel):$(picks sequential):$(picks first)" "1 2 3:1:1"
  assert_equal "$(picks parallel 2)" "2"
  for bad in "first 1" "sequential 1,2" "parallel 4" "parallel 0" "parallel x"; do
    run chief_agent_review_picks $bad; assert_failure
  done
  cfg <<< "# no pool"
  run chief_agent_review_picks parallel 1; assert_failure; assert_output --partial "needs a pool"
}
