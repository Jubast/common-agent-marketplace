#!/usr/bin/env bash
# Test: does `copilot plugin marketplace add` + `copilot plugin install`
# actually work for every plugin registered in .claude-plugin/marketplace.json?
# (Copilot CLI accepts this location directly -- no separate
# .github/plugin/marketplace.json is maintained in this repo.)
#
# Runs in a throwaway $HOME AND a throwaway COPILOT_HOME (mktemp -d,
# discarded on exit) so this never touches the real, possibly-shared
# ~/.copilot/ config. HOME alone may not be enough: per GitHub's own docs,
# Copilot CLI's config directory defaults to ~/.copilot but can be
# relocated independently of HOME via COPILOT_HOME -- the same class of
# override that caused Claude Code's HOME-only isolation to leak (see
# test-claude-install.sh). Not empirically verified against a real
# `copilot` CLI leak in this environment (the CLI wasn't installed here to
# test against), so this override is applied defensively.
#
# A safety net (see cleanup()) also guards against a leak regardless of
# whether COPILOT_HOME turns out to be needed -- but it never touches or
# reads the operator's real HOME/config, on principle. Instead it uses a
# second, disposable, never-installed-into throwaway HOME as a control: if
# anything shows up there after the real throwaway ran its installs,
# isolation didn't hold, and the test fails loudly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$REPO_ROOT/.claude-plugin/marketplace.json"

if ! command -v copilot &> /dev/null; then
    echo "ERROR: copilot CLI not found on PATH"
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
export COPILOT_HOME="$TEST_HOME/.copilot"

# Isolation safety net: CONTROL_HOME is a second throwaway HOME/config dir
# that nothing ever installs into. It starts empty and, if isolation is
# working, stays empty for the whole run. Checked once at the end, since a
# leak-causing env var would affect every command in this script identically,
# not just the first one.
control_plugin_ids() {
    HOME="$CONTROL_HOME" COPILOT_HOME="$CONTROL_HOME/.copilot" copilot plugin list 2>/dev/null \
        | grep -oE '[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+' | sort -u || true
}

cleanup() {
    local exit_code=$? leaked
    leaked=$(control_plugin_ids)
    rm -rf "$TEST_HOME" "$CONTROL_HOME"

    if [ -n "$leaked" ]; then
        echo "" >&2
        echo "!!! ISOLATION FAILURE: the following plugin(s) showed up under a" >&2
        echo "!!! second, untouched throwaway HOME/COPILOT_HOME that this test" >&2
        echo "!!! never installed into -- HOME/COPILOT_HOME aren't actually" >&2
        echo "!!! confining installs the way they should:" >&2
        echo "$leaked" | sed 's/^/!!!   /' >&2
        exit 1
    fi
    exit "$exit_code"
}
trap cleanup EXIT

echo "=== Copilot CLI marketplace install test ==="
echo "Marketplace: $MARKETPLACE_NAME"
echo "Isolated HOME: $TEST_HOME"
echo "Isolated COPILOT_HOME: $COPILOT_HOME"
echo "Control HOME (never installed into, checked for leaks): $CONTROL_HOME"
echo ""

echo "Adding marketplace from $REPO_ROOT..."
if ! copilot plugin marketplace add "$REPO_ROOT"; then
    echo "  [FAIL] marketplace add failed"
    exit 1
fi
echo "  [PASS] marketplace added"
echo ""

overall_pass=0
overall_fail=0

while IFS= read -r plugin_name; do
    echo "Installing $plugin_name@$MARKETPLACE_NAME..."
    if ! copilot plugin install "$plugin_name@$MARKETPLACE_NAME"; then
        echo "  [FAIL] install failed: $plugin_name"
        overall_fail=$((overall_fail + 1))
        continue
    fi

    list_output=$(copilot plugin list 2>&1)
    if echo "$list_output" | grep -q "$plugin_name@$MARKETPLACE_NAME"; then
        echo "  [PASS] $plugin_name installed"
        overall_pass=$((overall_pass + 1))
    else
        echo "  [FAIL] $plugin_name not showing as installed"
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
