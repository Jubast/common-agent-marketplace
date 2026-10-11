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
output=$(run_claude "According to the dispatch skill's 'Deciding builder vs researcher vs brainstormer' section, is 'builder' the default mode for dispatching work? Answer using exactly this structure:
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

echo "Test 5: A brainstormer is explicit-only..."
output=$(run_claude "According to the dispatch skill, may you spawn a brainstormer on your own when the operator's request is vague, or only when the operator explicitly asks to brainstorm? Answer using exactly this structure:
Spawns a brainstormer on its own: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Spawns a brainstormer on its own:.*no" "Brainstormer is spawned only on the operator's explicit request"
echo ""

echo "Test 6: The operator talks to the brainstormer directly..."
output=$(run_claude "According to the dispatch skill's brainstormer section, after spawning a brainstormer, do you relay the conversation between the operator and the brainstormer, or does the operator attach to its pane and talk to it directly? Answer using exactly this structure:
Relays the conversation: <yes or no>
Operator attaches to the pane: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Relays the conversation:.*no" "Chief never relays the brainstormer conversation"
assert_contains "$output" "Operator attaches to the pane:.*yes" "The operator attaches to the brainstormer's pane"
echo ""

echo "Test 7: A researcher can hand off to a brainstormer..."
output=$(run_claude "According to the dispatch skill's handoff section, can a done researcher hand off to a brainstormer, and can a done brainstormer hand off to a builder? Answer using exactly this structure:
Researcher to brainstormer: <yes or no>
Brainstormer to builder: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Researcher to brainstormer:.*yes" "A researcher can hand off to a brainstormer"
assert_contains "$output" "Brainstormer to builder:.*yes" "A brainstormer can hand off to a builder"
echo ""

echo "=== All dispatch skill tests passed ==="
