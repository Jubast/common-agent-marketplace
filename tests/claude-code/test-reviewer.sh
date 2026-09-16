#!/usr/bin/env bash
# Test: reviewer skill content and trigger conditions.
# Description-recall style, matching test-conventional-commits.sh - checks
# what SKILL.md claims, not a real review run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: reviewer skill ==="
echo ""

echo "Test 1: Used before merging a ship task..."
output=$(run_claude "According to the reviewer skill's description, is it meant to be used before merging a builder's ship task? Answer using exactly this structure:
Used before merging a ship task: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Used before merging a ship task:.*yes" "Used before merging a ship task"
echo ""

echo "Test 2: First checklist item is intent match..."
output=$(run_claude "According to the reviewer skill's checklist, is the first item checking whether the diff matches the task's operator intent - nothing more, nothing less? Answer using exactly this structure:
First checklist item is matching intent: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "First checklist item is matching intent:.*yes" "First checklist item checks intent match"
echo ""

echo "Test 3: Report format is PASS or FAIL with a reason..."
output=$(run_claude "According to the reviewer skill, does it report either PASS, or FAIL followed by the specific checklist item and a one-line reason, for each failed check? Answer using exactly this structure:
Reports PASS or per-item FAIL with a reason: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Reports PASS or per-item FAIL with a reason:.*yes" "Reports PASS or itemized FAIL with reasons"
echo ""

echo "Test 4: Flags unasked-for scope instead of silently keeping it..."
output=$(run_claude "According to the reviewer skill's scope discipline checklist item, if a diff contains a generalization or extra hardening nobody asked for, should that be flagged, or silently kept as long as it doesn't break anything? Answer using exactly this structure:
Silently keeps unasked-for scope: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Silently keeps unasked-for scope:.*no" "Flags unasked-for scope rather than silently keeping it"
echo ""

echo "=== All reviewer skill tests passed ==="
