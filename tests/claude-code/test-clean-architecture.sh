#!/usr/bin/env bash
# Test: clean-architecture skill content and trigger conditions.
# Description-recall style, matching test-clean-code.sh — checks what
# SKILL.md claims, not a real end-to-end review run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: clean-architecture skill ==="
echo ""

echo "Test 1: Explicit-invocation trigger..."
output=$(run_claude "According to the clean-architecture skill's description, does it trigger automatically on a generic 'review this code' request that never mentions Clean Architecture, the dependency rule, or Uncle Bob by name? Does it trigger when the user says 'does this follow the dependency rule?'? Answer using exactly this structure:
Triggers on generic review request: <yes or no>
Triggers on 'does this follow the dependency rule?': <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Triggers on generic review request:.*no" "Does not trigger on generic review request"
assert_contains "$output" "Triggers on 'does this follow the dependency rule?':.*yes" "Triggers on explicit dependency-rule phrasing"
echo ""

echo "Test 2: Target platform and programming-paradigms scope..."
output=$(run_claude "According to the clean-architecture skill, what language or platform does it target, and does it cover the book's programming-paradigms chapters (structured, object-oriented, functional programming)? Answer using exactly this structure:
Target platform: <answer>
Covers programming-paradigms chapters: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Target platform:.*NET" "Targets C#/.NET"
assert_contains "$output" "Covers programming-paradigms chapters:.*no" "Programming-paradigms chapters out of scope"
echo ""

echo "Test 3: Curated topic coverage..."
output=$(run_claude "According to the clean-architecture skill, list all of its curated topic areas (the ones with a dedicated reference file). Name each one by its exact reference file base name — the \`references/<slug>.md\` slug, without the \`.md\` extension. Answer as a comma-separated list." "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "dependency-rule" "Lists dependency-rule as a topic"
assert_contains "$output" "screaming-architecture" "Lists screaming-architecture as a topic"
# This skill's exact hyphenated slug — a model answering from general Clean
# Architecture knowledge, without SKILL.md loaded, is unlikely to produce it verbatim.
assert_contains "$output" "boundaries-and-dtos" "Lists boundaries-and-dtos by its exact slug"
echo ""

echo "Test 4: Review-mode reporting..."
output=$(run_claude "According to the clean-architecture skill, in review mode, what tool does it use to report findings, and what does it do if the reviewed code has no violations at all? Answer using exactly this structure:
Reporting tool: <tool name>
No violations found: <what it does>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Reporting tool:.*ReportFindings" "Uses ReportFindings tool"
assert_contains "$output" "No violations found:.*empty" "Calls ReportFindings with an empty list when clean"
echo ""

echo "=== All clean-architecture skill tests passed ==="
