#!/usr/bin/env bash
# test-agent.sh - agents/agent.sh loader: default, config file, unknown agent.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$(cd "$TEST_DIR/../.." && pwd)/plugins/chief/bin/lib"
. "$TEST_DIR/lib/harness.sh"

WORK=$(mktemp -d)
harness_trap 'rm -rf "$WORK"'
export CHIEF_HOME="$WORK/.chief"
unset CHIEF_AGENT

echo "test-agent:"

load() { bash -c '. "$1/paths.sh"; . "$1/agents/agent.sh"; agent_name' _ "$LIB" 2>&1; }

assert_eq "$(load)" "claude" "loader: defaults to claude"
mkdir -p "$CHIEF_HOME/config"; echo claude > "$CHIEF_HOME/config/agent"
assert_eq "$(load)" "claude" "loader: reads \$CONFIG/agent"
echo nope > "$CHIEF_HOME/config/agent"
assert_contains "$(load)" "unsupported agent 'nope'" "loader: unknown agent in config errors"
assert_contains "$(CHIEF_AGENT=bogus load)" "unsupported agent 'bogus'" "loader: unknown \$CHIEF_AGENT errors"
assert_contains "$(CHIEF_AGENT=../claude load)" "unsupported agent '../claude'" "loader: a name with a slash is refused"
assert_contains "$(CHIEF_AGENT=Claude load)" "unsupported agent 'Claude'" "loader: only [a-z0-9-] names are accepted"

harness_summary
