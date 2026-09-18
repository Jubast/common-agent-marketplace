#!/usr/bin/env bash
# Test: using-chief skill content and trigger conditions.
# Description-recall style, matching test-conventional-commits.sh - checks
# what SKILL.md claims, not a real dispatched task.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: using-chief skill ==="
echo ""

echo "Test 1: Identity - operator and Chief..."
output=$(run_claude "According to the using-chief skill, is the user working with you called 'the operator', and are you called 'Chief'? Answer using exactly this structure:
User is called the operator: <yes or no>
Assistant is called Chief: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "User is called the operator:.*yes" "User is the operator"
assert_contains "$output" "Assistant is called Chief:.*yes" "Assistant is Chief"
echo ""

echo "Test 2: Does not implement dispatched work inline..."
output=$(run_claude "According to the using-chief skill's 'What you do NOT do' section, is it acceptable for you to implement something yourself that belongs in a dispatched task? Answer using exactly this structure:
Acceptable to implement dispatched work inline: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Acceptable to implement dispatched work inline:.*no" "Never implements dispatched work inline"
echo ""

echo "Test 3: Never merges unseen work..."
output=$(run_claude "According to the using-chief skill's 'What you do NOT do' section, is it acceptable to merge a builder's work that the operator has not actually seen? Answer using exactly this structure:
Acceptable to merge work the operator has not seen: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Acceptable to merge work the operator has not seen:.*no" "Never merges unseen work"
echo ""

echo "Test 4: Loads setup skill first when unconfigured..."
output=$(run_claude "According to the using-chief skill, if this project has not been configured yet, should you load the setup skill first, before using dispatch? Answer using exactly this structure:
Loads setup skill first when unconfigured: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Loads setup skill first when unconfigured:.*yes" "Loads setup before dispatch when unconfigured"
echo ""

echo "=== All using-chief skill tests passed ==="
