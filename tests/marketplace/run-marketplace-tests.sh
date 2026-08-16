#!/usr/bin/env bash
# Test runner for this repo's marketplace-install tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo " common-agent-marketplace Install Test Suite"
echo "========================================"
echo ""

tests=(
    "test-claude-install.sh"
    "test-copilot-install.sh"
)

passed=0
failed=0
skipped=0

for test in "${tests[@]}"; do
    echo "----------------------------------------"
    echo "Running: $test"
    echo "----------------------------------------"

    test_path="$SCRIPT_DIR/$test"

    if [ ! -f "$test_path" ]; then
        echo "  [SKIP] Test file not found: $test"
        skipped=$((skipped + 1))
        continue
    fi

    if [ ! -x "$test_path" ]; then
        chmod +x "$test_path"
    fi

    if output=$(bash "$test_path" 2>&1); then
        echo "$output" | sed 's/^/  /'
        echo "  [PASS]"
        passed=$((passed + 1))
    else
        echo "$output" | sed 's/^/  /'
        echo "  [FAIL]"
        failed=$((failed + 1))
    fi

    echo ""
done

echo "========================================"
echo " Test Results Summary"
echo "========================================"
echo ""
echo "  Passed:  $passed"
echo "  Failed:  $failed"
echo "  Skipped: $skipped"
echo ""

if [ $failed -gt 0 ]; then
    echo "STATUS: FAILED"
    exit 1
else
    echo "STATUS: PASSED"
    exit 0
fi
