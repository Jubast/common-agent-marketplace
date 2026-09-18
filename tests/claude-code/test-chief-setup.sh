#!/usr/bin/env bash
# Test: chief's setup skill content and trigger conditions.
# Description-recall style, matching test-conventional-commits.sh - checks
# what SKILL.md claims, not a real chief-setup.sh run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: chief setup skill ==="
echo ""

echo "Test 1: Only needed once, when unconfigured..."
output=$(run_claude "According to chief's setup skill, is it only needed once per project, when .chief/config/backend doesn't exist yet? Answer using exactly this structure:
Only needed once when unconfigured: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Only needed once when unconfigured:.*yes" "Only needed once, when unconfigured"
echo ""

echo "Test 2: Backend choice is herdr or orca..."
output=$(run_claude "According to chief's setup skill, does it ask the operator to choose between the herdr and orca backends? Answer using exactly this structure:
Asks to choose herdr or orca: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Asks to choose herdr or orca:.*yes" "Asks operator to choose herdr or orca"
echo ""

echo "Test 3: chief-setup.sh is safe to re-run..."
output=$(run_claude "According to chief's setup skill, is running bin/chief-setup.sh safe to re-run? Answer using exactly this structure:
Safe to re-run chief-setup.sh: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Safe to re-run chief-setup.sh:.*yes" "chief-setup.sh is safe to re-run"
echo ""

echo "Test 4: Not used again once configured..."
output=$(run_claude "According to chief's setup skill's own description, should it be used again once Chief is already configured for a project, or does the dispatch skill own everything after that? Answer using exactly this structure:
Used again once already configured: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Used again once already configured:.*no" "Not reused once already configured - dispatch takes over"
echo ""

echo "=== All chief setup skill tests passed ==="
