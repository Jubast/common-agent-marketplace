#!/usr/bin/env bash
# Test: does `claude plugin marketplace add` + `claude plugin install`
# actually work for every plugin registered in .claude-plugin/marketplace.json?
#
# Runs in a throwaway $HOME AND a throwaway CLAUDE_CONFIG_DIR (mktemp -d,
# discarded on exit) so this never touches the real, possibly-shared
# ~/.claude config. HOME alone is not enough: Claude Code resolves its
# config directory from $CLAUDE_CONFIG_DIR when that's set in the
# environment, ignoring $HOME entirely -- and this repo's own devcontainers
# (.devcontainer/chief, .devcontainer/orca) set CLAUDE_CONFIG_DIR globally.
#
# A safety net (see cleanup()) also guards against a leak regardless of
# whether the env-var isolation above holds -- but it never touches or reads
# the operator's real HOME/config either, on principle (probing or "fixing"
# real global state from an unattended test run is exactly how a previous
# investigation into this same bug ended up leaving that config worse off
# than it started). Instead it uses a second, disposable, never-installed-into
# throwaway HOME as a control: if anything shows up there after the real
# throwaway ran its installs, isolation didn't hold, and the test fails
# loudly. Both throwaways are torn down on exit either way.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$REPO_ROOT/.claude-plugin/marketplace.json"

if ! command -v claude &> /dev/null; then
    echo "ERROR: claude CLI not found on PATH"
    exit 1
fi

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: manifest not found: $MANIFEST"
    exit 1
fi

MARKETPLACE_NAME=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['name'])")
PLUGIN_NAMES=$(python3 -c "
import json
data = json.load(open('$MANIFEST'))
for p in data['plugins']:
    print(p['name'])
")

if [ -z "$PLUGIN_NAMES" ]; then
    echo "ERROR: no plugins found in $MANIFEST"
    exit 1
fi

TEST_HOME=$(mktemp -d)
CONTROL_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
export CLAUDE_CONFIG_DIR="$TEST_HOME/.claude"

# Isolation safety net: CONTROL_HOME is a second throwaway HOME/config dir
# that nothing ever installs into. It starts empty and, if isolation is
# working, stays empty for the whole run -- it has no way to see TEST_HOME's
# installs except through a real leak. Checked once at the end, since a
# leak-causing env var (like the ambient CLAUDE_CONFIG_DIR that caused this
# bug) would affect every command in this script identically, not just the
# first one.
control_plugin_ids() {
    HOME="$CONTROL_HOME" CLAUDE_CONFIG_DIR="$CONTROL_HOME/.claude" claude plugin list 2>/dev/null \
        | grep -oE '[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+' | sort -u || true
}

cleanup() {
    local exit_code=$? leaked
    leaked=$(control_plugin_ids)
    rm -rf "$TEST_HOME" "$CONTROL_HOME"

    if [ -n "$leaked" ]; then
        echo "" >&2
        echo "!!! ISOLATION FAILURE: the following plugin(s) showed up under a" >&2
        echo "!!! second, untouched throwaway HOME/CLAUDE_CONFIG_DIR that this" >&2
        echo "!!! test never installed into -- HOME/CLAUDE_CONFIG_DIR aren't" >&2
        echo "!!! actually confining installs the way they should:" >&2
        echo "$leaked" | sed 's/^/!!!   /' >&2
        exit 1
    fi
    exit "$exit_code"
}
trap cleanup EXIT

echo "=== Claude Code marketplace install test ==="
echo "Marketplace: $MARKETPLACE_NAME"
echo "Isolated HOME: $TEST_HOME"
echo "Isolated CLAUDE_CONFIG_DIR: $CLAUDE_CONFIG_DIR"
echo "Control HOME (never installed into, checked for leaks): $CONTROL_HOME"
echo ""

echo "Adding marketplace from $REPO_ROOT..."
if ! claude plugin marketplace add "$REPO_ROOT"; then
    echo "  [FAIL] marketplace add failed"
    exit 1
fi
echo "  [PASS] marketplace added"
echo ""

overall_pass=0
overall_fail=0

while IFS= read -r plugin_name; do
    echo "Installing $plugin_name@$MARKETPLACE_NAME..."
    if ! claude plugin install "$plugin_name@$MARKETPLACE_NAME" -y; then
        echo "  [FAIL] install failed: $plugin_name"
        overall_fail=$((overall_fail + 1))
        continue
    fi

    list_output=$(claude plugin list 2>&1)
    if echo "$list_output" | grep -A3 "$plugin_name@$MARKETPLACE_NAME" | grep -q "enabled"; then
        echo "  [PASS] $plugin_name installed and enabled"
        overall_pass=$((overall_pass + 1))
    else
        echo "  [FAIL] $plugin_name not showing as installed/enabled"
        echo "$list_output" | sed 's/^/    /'
        overall_fail=$((overall_fail + 1))
    fi
    echo ""
done <<< "$PLUGIN_NAMES"

echo "=== Results: $overall_pass passed, $overall_fail failed ==="
if [ "$overall_fail" -gt 0 ]; then
    exit 1
fi
exit 0
