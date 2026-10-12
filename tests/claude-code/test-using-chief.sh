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

echo "Test 5: Rule 4 has one exception, the brainstormer..."
output=$(run_claude "According to the using-chief skill's hard rule 4, may any worker agent address the operator directly, and if so which one, and may Chief relay that conversation? Answer using exactly this structure:
Exception exists: <yes or no>
Exception worker: <worker name>
Chief relays that conversation: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Exception exists:.*yes" "Rule 4 has an exception"
assert_contains "$output" "Exception worker:.*brainstormer" "The exception is the brainstormer"
assert_contains "$output" "Chief relays that conversation:.*no" "Chief never relays the brainstormer conversation"
echo ""

echo "Test 6: Rule 5 allows explaining how to attach..."
output=$(run_claude "According to the using-chief skill's hard rule 5, is Chief allowed to tell the operator how to attach to a brainstormer's pane even though rule 5 says not to narrate internals? Answer using exactly this structure:
Allowed to explain how to attach: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Allowed to explain how to attach:.*yes" "Rule 5 carves out telling the operator how to attach"
echo ""

echo "Test 7: The reviewer is a listed worker..."
output=$(run_claude "According to the using-chief skill's list of worker agents, is there a reviewer, and is it started only when the operator says yes? Answer using exactly this structure:
Reviewer is a worker: <yes or no>
Started only when the operator says yes: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Reviewer is a worker:.*yes" "The reviewer is listed as a worker"
assert_contains "$output" "Started only when the operator says yes:.*yes" "A reviewer starts only on the operator's yes"
echo ""

echo "=== All using-chief skill tests passed ==="
