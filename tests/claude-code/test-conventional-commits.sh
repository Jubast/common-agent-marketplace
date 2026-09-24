#!/usr/bin/env bash
# Test: conventional-commits skill content and trigger conditions.
# Description-recall style, matching test-clean-code.sh — checks what
# SKILL.md claims, not a real end-to-end commit run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: conventional-commits skill ==="
echo ""

echo "Test 1: Trigger conditions..."
output=$(run_claude "According to the conventional-commits skill's description, does it trigger when the user wants to commit their changes or invokes /commit? Answer using exactly this structure:
Triggers on commit request: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Triggers on commit request:.*yes" "Triggers on commit request or /commit"
echo ""

echo "Test 2: No upfront approval gate before committing..."
output=$(run_claude "According to the conventional-commits skill, after it groups related changes for a commit, does it wait for the user to approve the group with a yes/no response before staging and committing it, or does it stage and commit the group directly using its own judgment? Answer using exactly this structure:
Waits for yes/no approval before committing: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Waits for yes/no approval before committing:.*no" "Commits each group directly without an approval gate"
echo ""

echo "Test 3: Attribution rules..."
output=$(run_claude "According to the conventional-commits skill's Important Rules section, is the agent allowed to add 'Co-authored-by' trailers to commit messages? Answer using exactly this structure:
Allowed to add Co-authored-by trailers: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Allowed to add Co-authored-by trailers:.*no" "Never adds Co-authored-by trailers"
echo ""

echo "Test 4: Stops after committing, no push or PR offer..."
output=$(run_claude "According to the conventional-commits skill, once all commits are made, does the skill go on to push the branch or offer to open or update a pull request? Answer using exactly this structure:
Pushes or offers a pull request after committing: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Pushes or offers a pull request after committing:.*no" "Stops once all commits are made, without pushing or offering a PR"
echo ""

echo "=== All conventional-commits skill tests passed ==="
