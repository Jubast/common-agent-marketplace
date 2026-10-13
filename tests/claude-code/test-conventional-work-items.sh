#!/usr/bin/env bash
# Test: conventional-work-items skill content and trigger conditions.
# Description-recall style, matching test-conventional-commits.sh - checks
# what SKILL.md claims, not a real end-to-end issue filed against a tracker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: conventional-work-items skill ==="
echo ""

echo "Test 1: Trigger conditions..."
output=$(run_claude "According to the conventional-work-items skill's description, does it trigger when the user wants to open, create, or update an issue, task, or ticket? Answer using exactly this structure:
Triggers on issue request: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Triggers on issue request:.*yes" "Triggers on issue/task/ticket open, create, or update requests"
echo ""

echo "Test 2: Defines its own title grammar..."
output=$(run_claude "According to the conventional-work-items skill, does it define its own title grammar (a type prefix format with a table of types like bug/feature/chore), or does it say issues have no fixed title convention? Answer using exactly this structure:
Defines its own title grammar: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Defines its own title grammar:.*yes" "Defines a type-prefix title grammar instead of leaving it unspecified"
echo ""

echo "Test 3: Plain-issue description template sections..."
output=$(run_claude "According to the conventional-work-items skill's bundled plain-issue description template (templates/plain-issue.md, the flat-model fallback used when the tracker has no work-item types), does it include a 'Repro' section, an 'Environment' section, and an 'Out of Scope' section? Answer using exactly this structure:
Includes Repro section: <yes or no>
Includes Environment section: <yes or no>
Includes Out of Scope section: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Includes Repro section:.*yes" "Plain issue template includes a Repro section"
assert_contains "$output" "Includes Environment section:.*yes" "Plain issue template includes an Environment section"
assert_contains "$output" "Includes Out of Scope section:.*no" "Plain issue template does not include an Out of Scope section"
echo ""

echo "Test 4: Native work-item types..."
output=$(run_claude "According to the conventional-work-items skill: does it tell the agent to use the tracker's own work-item types (picked by role) and never invent a type the tracker lacks? When the tracker carries the type natively, does it say to leave the type prefix out of the title? When the tracker has no work-item types or they can't be determined, does it fall back to the flat plain-issue model with the type-prefix title? Answer using exactly this structure:
Uses tracker's native types: <yes or no>
Omits title prefix when type is native: <yes or no>
Falls back to flat model: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Uses tracker's native types:.*yes" "Uses the tracker's native work-item types"
assert_contains "$output" "Omits title prefix when type is native:.*yes" "Omits the type prefix from the title when the tracker carries the type"
assert_contains "$output" "Falls back to flat model:.*yes" "Falls back to the flat model when types are not distinguished"
echo ""

echo "Test 5: Relations and child items..."
output=$(run_claude "According to the conventional-work-items skill: does it tell the agent to relate work items with the tracker's native links? Does it tell the agent to automatically create child items regardless of the request or project conventions? Answer using exactly this structure:
Uses native tracker links: <yes or no>
Auto-creates child items: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Uses native tracker links:.*yes" "Relates work items with native tracker links"
assert_contains "$output" "Auto-creates child items:.*no" "Does not auto-create child items"
echo ""

echo "Test 6: Template locations and default loading..."
output=$(run_claude "According to the conventional-work-items skill, (a) does it name the in-repo project template locations .github/ISSUE_TEMPLATE/, .gitlab/issue_templates/ and a platform-neutral .work-items/templates/ path, and (b) when falling back to its bundled templates, does it say to read only the one template file for the chosen role? Answer using exactly this structure:
Names template locations: <yes or no>
Reads only the chosen role's template: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Names template locations:.*yes" "Names the project template locations"
assert_contains "$output" "Reads only the chosen role's template:.*yes" "Reads only the chosen role's bundled template"
echo ""

echo "Test 7: No Definition of Ready/Done gate..."
output=$(run_claude "According to the conventional-work-items skill, does it include a step for checking the project's Definition of Ready or Definition of Done before filing or closing the issue? Answer using exactly this structure:
Checks Definition of Ready or Done: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Checks Definition of Ready or Done:.*no" "Does not check or gate on a Definition of Ready/Done"
echo ""

echo "=== All conventional-work-items skill tests passed ==="
