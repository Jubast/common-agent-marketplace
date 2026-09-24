#!/usr/bin/env bash
# Test: conventional-issues skill content and trigger conditions.
# Description-recall style, matching test-conventional-commits.sh - checks
# what SKILL.md claims, not a real end-to-end issue filed against a tracker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: conventional-issues skill ==="
echo ""

echo "Test 1: Trigger conditions..."
output=$(run_claude "According to the conventional-issues skill's description, does it trigger when the user wants to open, create, or update an issue, task, or ticket? Answer using exactly this structure:
Triggers on issue request: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Triggers on issue request:.*yes" "Triggers on issue/task/ticket open, create, or update requests"
echo ""

echo "Test 2: Defines its own title grammar..."
output=$(run_claude "According to the conventional-issues skill, does it define its own title grammar (a type prefix format with a table of types like bug/feature/chore), or does it say issues have no fixed title convention? Answer using exactly this structure:
Defines its own title grammar: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Defines its own title grammar:.*yes" "Defines a type-prefix title grammar instead of leaving it unspecified"
echo ""

echo "Test 3: Default description template sections..."
output=$(run_claude "According to the conventional-issues skill's default description template (the fallback used when no platform or repo template exists), does it include a 'Repro' section, an 'Environment' section, and an 'Out of Scope' section? Answer using exactly this structure:
Includes Repro section: <yes or no>
Includes Environment section: <yes or no>
Includes Out of Scope section: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Includes Repro section:.*yes" "Default template includes a Repro section"
assert_contains "$output" "Includes Environment section:.*yes" "Default template includes an Environment section"
assert_contains "$output" "Includes Out of Scope section:.*no" "Default template does not include an Out of Scope section"
echo ""

echo "Test 4: No Definition of Ready/Done gate..."
output=$(run_claude "According to the conventional-issues skill, does it include a step for checking the project's Definition of Ready or Definition of Done before filing or closing the issue? Answer using exactly this structure:
Checks Definition of Ready or Done: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Checks Definition of Ready or Done:.*no" "Does not check or gate on a Definition of Ready/Done"
echo ""

echo "=== All conventional-issues skill tests passed ==="
