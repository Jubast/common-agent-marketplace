#!/usr/bin/env bash
# Test: dispatch skill content and trigger conditions.
# Description-recall style, matching test-conventional-commits.sh - checks
# what SKILL.md claims, not a real spawned builder/researcher.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: dispatch skill ==="
echo ""

echo "Test 1: builder is the default mode..."
output=$(run_claude "According to the dispatch skill's 'Deciding builder vs researcher' section, is 'builder' the default mode for dispatching work? Answer using exactly this structure:
Builder is the default mode: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Builder is the default mode:.*yes" "Builder is the default dispatch mode"
echo ""

echo "Test 2: Researchers are not for ordinary ambiguity..."
output=$(run_claude "According to the dispatch skill, should you launch a researcher to resolve ordinary ambiguity, or should you ask one concise question instead? Answer using exactly this structure:
Launches a researcher for ordinary ambiguity: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Launches a researcher for ordinary ambiguity:.*no" "Asks instead of researching for ordinary ambiguity"
echo ""

echo "Test 3: Merging is always the operator's call..."
output=$(run_claude "According to the dispatch skill's lifecycle section on merging, does Chief ever merge a builder's work on its own initiative, or is merging always the operator's call after they've looked at the diff? Answer using exactly this structure:
Merges on its own initiative: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Merges on its own initiative:.*no" "Merging is never automatic"
echo ""

echo "Test 4: Escalation tries interrupt before relaunch..."
output=$(run_claude "According to the dispatch skill's escalation step for a stuck task, should you try chief-control.sh interrupt before resorting to chief-control.sh relaunch? Answer using exactly this structure:
Tries interrupt before relaunch: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Tries interrupt before relaunch:.*yes" "Escalates cheapest-first: interrupt before relaunch"
echo ""

echo "=== All dispatch skill tests passed ==="
