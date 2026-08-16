#!/usr/bin/env bash
# Test: does `copilot plugin marketplace add` + `copilot plugin install`
# actually work for every plugin registered in .claude-plugin/marketplace.json?
# (Copilot CLI accepts this location directly -- no separate
# .github/plugin/marketplace.json is maintained in this repo.)
#
# Runs in a throwaway $HOME (mktemp -d, discarded on exit) so this never
# touches the real, possibly-shared ~/.copilot/ config.
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
cleanup() {
    rm -rf "$TEST_HOME"
}
trap cleanup EXIT

echo "=== Copilot CLI marketplace install test ==="
echo "Marketplace: $MARKETPLACE_NAME"
echo "Isolated HOME: $TEST_HOME"
echo ""

echo "Adding marketplace from $REPO_ROOT..."
if ! HOME="$TEST_HOME" copilot plugin marketplace add "$REPO_ROOT"; then
    echo "  [FAIL] marketplace add failed"
    exit 1
fi
echo "  [PASS] marketplace added"
echo ""

overall_pass=0
overall_fail=0

while IFS= read -r plugin_name; do
    echo "Installing $plugin_name@$MARKETPLACE_NAME..."
    if ! HOME="$TEST_HOME" copilot plugin install "$plugin_name@$MARKETPLACE_NAME"; then
        echo "  [FAIL] install failed: $plugin_name"
        overall_fail=$((overall_fail + 1))
        continue
    fi

    list_output=$(HOME="$TEST_HOME" copilot plugin list 2>&1)
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
