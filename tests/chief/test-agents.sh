#!/usr/bin/env bash
# test-agents.sh - chief-agents.sh: the effective agent per role, read-only.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

WORK=$(mktemp -d)
harness_trap 'rm -rf "$WORK"'
export CHIEF_HOME="$WORK/.chief"
mkdir -p "$CHIEF_HOME/config"
CFG="$CHIEF_HOME/config/agents"
STATE="$CHIEF_HOME/state"

echo "test-agents:"

out=$("$BIN/chief-agents.sh" | tr -s ' ')
assert_eq "$(wc -l <<< "$out")" "4" "no config: one line per role"
assert_contains "$out" "builder: claude (no pool configured)" "no config: claude default, flagged"

printf 'claude:opus\n[builder]\ncodex:gpt-5\n[reviewer]\ncopilot\n' > "$CFG"
out=$("$BIN/chief-agents.sh" | tr -s ' ')
assert_contains "$out" "builder: codex:gpt-5" "a role's own pool"
assert_not_contains "$(grep '^builder' <<< "$out")" "fallback" "a role's own pool has no marker"
assert_contains "$out" "reviewer: copilot" "reviewer has its own pool"
assert_contains "$out" "researcher: claude:opus (global fallback)" "a role without a pool is marked as the global fallback"
assert_contains "$out" "brainstormer: claude:opus (global fallback)" "brainstormer falls back too"

printf 'strategy = round-robin\n[builder]\ncodex:gpt-5\nclaude:sonnet\n' > "$CFG"
"$BIN/chief-agents.sh" >/dev/null; "$BIN/chief-agents.sh" >/dev/null
assert_contains "$("$BIN/chief-agents.sh" | tr -s ' ')" "builder: codex:gpt-5" "round-robin: read-only, the cursor does not move"
assert_file_missing "$STATE/agent-cursor-builder" "round-robin: no cursor file written"

printf 'strategy = weighted\n[builder]\ncodex:gpt-5 weight=2\nclaude:sonnet\n' > "$CFG"
assert_contains "$("$BIN/chief-agents.sh" | tr -s ' ')" "builder: weighted pool: codex:gpt-5 (2), claude:sonnet (1)" "weighted: the pool is listed"

printf '[prod]\n' > "$CFG"
assert_failure "a bad config fails loudly" -- "$BIN/chief-agents.sh"

harness_summary
