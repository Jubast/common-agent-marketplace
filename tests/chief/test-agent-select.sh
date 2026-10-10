#!/usr/bin/env bash
# test-agent-select.sh - agents/agent.sh: the .chief/config/agents file and its strategies.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$(cd "$TEST_DIR/../.." && pwd)/plugins/chief/bin/lib"
. "$TEST_DIR/lib/harness.sh"

WORK=$(mktemp -d)
harness_trap 'rm -rf "$WORK"'
export CHIEF_HOME="$WORK/.chief"
. "$LIB/paths.sh"
. "$LIB/agents/agent.sh"
CFG="$CONFIG/agents"

echo "test-agent-select:"

# pick <mode> -> "agent:model|command" of the selection (current shell, so cursors persist)
pick() { chief_agent_select "$1" && echo "$SEL_AGENT:$SEL_MODEL|$SEL_COMMAND"; }
cfg() { cat > "$CFG"; }

assert_eq "$(pick ship)" "claude:|" "no config: claude, default model"
cfg <<< "# only comments"
assert_eq "$(pick ship)" "claude:|" "a config with no pool: claude"

cfg <<'EOF2'
# the pool

claude:opus
codex:gpt-5   # trailing comment
EOF2
assert_eq "$(pick ship)" "claude:opus|" "first: the first entry (strategy omitted)"
assert_eq "$(pick ship)" "claude:opus|" "first: always the same"

cfg <<'EOF2'
strategy = round-robin   # rotate
claude:opus
codex:gpt-5
copilot
EOF2
assert_eq "$(pick ship; pick ship; pick ship; pick ship)" "claude:opus|
codex:gpt-5|
copilot:|
claude:opus|" "round-robin: rotates and wraps"
assert_eq "$(cat "$STATE/agent-cursor-builder")" "4" "round-robin: the cursor is persisted"
assert_eq "$(pick scout)" "claude:opus|" "round-robin: each mode has its own cursor"
printf 'junk' > "$STATE/agent-cursor-builder"
assert_eq "$(pick ship)" "claude:opus|" "round-robin: a corrupt cursor restarts at the first entry"

rm -f "$STATE"/agent-cursor-*
for i in 1 2 3 4 5 6; do (chief_agent_select ship; echo "$SEL_AGENT:$SEL_MODEL") & done > "$WORK/par.out"; wait
assert_eq "$(sort "$WORK/par.out" | uniq -c | awk '{print $1}' | tr '\n' ' ')" "2 2 2 " "round-robin: parallel spawns never pick the same entry twice in a row"

cfg <<'EOF2'
strategy = weighted
claude:opus   weight=3
codex:gpt-5   weight=2
copilot       weight=1
EOF2
w() { CHIEF_AGENT_RANDOM=$1 pick ship; }
assert_eq "$(w 0; w 2; w 3; w 4; w 5; w 6)" "claude:opus|
claude:opus|
codex:gpt-5|
codex:gpt-5|
copilot:|
claude:opus|" "weighted: the injected random walks the weight ranges"
cfg <<'EOF2'
strategy = weighted
claude weight=0
codex
EOF2
assert_eq "$(w 0; w 7)" "codex:|
codex:|" "weighted: weight=0 is never picked"
cfg <<'EOF2'
strategy = weighted
claude weight=0
EOF2
assert_contains "$(pick ship 2>&1)" "every weight is 0" "weighted: all zero errors"

cfg <<'EOF2'
strategy = random
claude weight=100
codex
EOF2
assert_eq "$(w 0; w 1; w 2)" "claude:|
codex:|
claude:|" "random: equal weights, ignoring weight="

cfg <<'EOF2'
strategy = first
claude:opus
[scout]
strategy = round-robin
claude:haiku
codex:gpt-5-mini
[builder]
codex:gpt-5
EOF2
rm -f "$STATE"/agent-cursor-*
assert_eq "$(pick scout; pick scout)" "claude:haiku|
codex:gpt-5-mini|" "sections: a scout pool with its own strategy"
assert_eq "$(pick ship)" "codex:gpt-5|" "sections: a ship pool inherits the global strategy"
cfg <<'EOF2'
strategy = round-robin
claude:opus
[scout]
codex
EOF2
rm -f "$STATE"/agent-cursor-*
assert_eq "$(pick ship; pick ship)" "claude:opus|
claude:opus|" "sections: a mode without a section uses the global pool (one entry here)"
assert_eq "$(pick scout)" "codex:|" "sections: the scout pool wins over the global one"

cfg <<'EOF2'
claude:opus args="--verbose --add-dir /x" weight=2 command="wrap"
codex args="--search"
EOF2
assert_eq "$(chief_agent_select ship; echo "$SEL_AGENT|$SEL_ARGS|$SEL_COMMAND")" "claude|--verbose --add-dir /x|wrap" "args: parsed next to weight and command, in any order"
cfg <<'EOF2'
strategy = round-robin
claude:opus
codex:gpt-5 args="--search"
EOF2
rm -f "$STATE"/agent-cursor-*
assert_eq "$(chief_agent_select ship; chief_agent_select ship; echo "$SEL_AGENT|$SEL_ARGS")" "codex|--search" "args: an entry without args does not leak into the next pick"
cfg <<'EOF2'
claude:opus command="/opt/bin/claude --dangerously-skip-permissions --foo # x" weight=2
EOF2
assert_eq "$(pick ship)" "claude:opus|/opt/bin/claude --dangerously-skip-permissions --foo # x" "command: kept verbatim, in either option order"

# builder (mode ship) and scout pools: builder-only, scout-only, both, neither
cfg <<'EOF2'
claude:opus
[builder]
codex:gpt-5
EOF2
assert_eq "$(pick ship; pick scout)" "codex:gpt-5|
claude:opus|" "builder-only: ship uses [builder], scout falls back to the global pool"
cfg <<'EOF2'
claude:opus
[scout]
copilot
EOF2
assert_eq "$(pick ship; pick scout)" "claude:opus|
copilot:|" "scout-only: scout uses [scout], ship falls back to the global pool"
cfg <<'EOF2'
[builder]
codex:gpt-5
[scout]
copilot
EOF2
assert_eq "$(pick ship; pick scout)" "codex:gpt-5|
copilot:|" "both: each mode uses its own pool, no global pool needed"
cfg <<'EOF2'
claude:opus
EOF2
assert_eq "$(pick ship; pick scout)" "claude:opus|
claude:opus|" "neither: both modes use the global pool"

bad() { cfg; chief_agent_select "${1:-ship}" 2>&1; }
assert_contains "$(bad <<< 'strategy = sometimes')" "unknown strategy 'sometimes'" "error: unknown strategy"
assert_contains "$(bad <<< '[ship]')" "unknown section [ship]" "error: [ship] is not a section (builder or scout)"
assert_contains "$(bad <<< '[prod]')" "unknown section [prod]" "error: unknown section"
assert_contains "$(bad <<< 'Claude')" "bad profile 'Claude'" "error: bad agent name"
assert_contains "$(bad <<< 'claude:opus weight=x')" "unexpected ' weight=x'" "error: malformed weight"
assert_contains "$(bad <<< 'claude args="--x')" "unexpected" "error: unterminated args"
assert_contains "$(bad <<< 'claude:opus color=red')" "unexpected ' color=red'" "error: unknown option"
assert_contains "$(bad <<< 'claude:op us')" "unexpected ' us'" "error: a space inside the profile"
assert_contains "$(bad <<< 'claude command="unterminated')" "unexpected" "error: unterminated command"
assert_contains "$(bad <<< 'claude:$(rm)')" "bad profile" "error: shell metacharacters in the model"
assert_contains "$(bad <<< $'claude\ncodex x')" "agents:2:" "error: names the file line"

harness_summary
