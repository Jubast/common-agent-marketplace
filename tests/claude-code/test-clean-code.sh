#!/usr/bin/env bash
# Test: clean-code skill content and trigger conditions.
# Description-recall style, matching test-convert-pdf-to-md.sh — checks
# what SKILL.md claims, not a real end-to-end review run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: clean-code skill ==="
echo ""

echo "Test 1: Explicit-invocation trigger..."
output=$(run_claude "According to the clean-code skill's description, does it trigger automatically on a generic 'review this code' request that never mentions Clean Code, Uncle Bob, or clean code principles by name? Does it trigger when the user says 'review this for clean code'? Answer using exactly this structure:
Triggers on generic review request: <yes or no>
Triggers on 'review this for clean code': <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Triggers on generic review request:.*no" "Does not trigger on generic review request"
assert_contains "$output" "Triggers on 'review this for clean code':.*yes" "Triggers on explicit clean-code phrasing"
echo ""

echo "Test 2: Target platform and concurrency scope..."
output=$(run_claude "According to the clean-code skill, what language or platform does it target, and does it cover the book's concurrency chapter? Answer using exactly this structure:
Target platform: <answer>
Covers concurrency chapter: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Target platform:.*NET" "Targets C#/.NET"
assert_contains "$output" "Covers concurrency chapter:.*no" "Concurrency chapter out of scope"
echo ""

echo "Test 3: Curated topic coverage..."
output=$(run_claude "According to the clean-code skill, list all of its curated topic areas (the ones with a dedicated reference file). Name each one by its exact reference file base name — the \`references/<slug>.md\` slug, without the \`.md\` extension. Answer as a comma-separated list." "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "naming" "Lists naming as a topic"
assert_contains "$output" "boundaries" "Lists boundaries as a topic"
# This skill's exact hyphenated slug — a model answering from general Clean
# Code knowledge, without SKILL.md loaded, is unlikely to produce it verbatim.
assert_contains "$output" "objects-and-data-structures" "Lists objects-and-data-structures by its exact slug"
echo ""

echo "Test 4: Review-mode reporting..."
output=$(run_claude "According to the clean-code skill, in review mode, what tool does it use to report findings, and what does it do if the reviewed code has no violations at all? Answer using exactly this structure:
Reporting tool: <tool name>
No violations found: <what it does>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Reporting tool:.*ReportFindings" "Uses ReportFindings tool"
assert_contains "$output" "No violations found:.*empty" "Calls ReportFindings with an empty list when clean"
echo ""

echo "=== All clean-code skill tests passed ==="
