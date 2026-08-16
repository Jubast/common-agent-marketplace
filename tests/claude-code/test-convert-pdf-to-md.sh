#!/usr/bin/env bash
# Test: convert-pdf-to-md skill content and requirements.
# Description-recall style, not real execution — see
# test-convert-pdf-to-md-integration.sh for end-to-end behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: convert-pdf-to-md skill ==="
echo ""

echo "Test 1: Implicit trigger recognition..."
output=$(run_claude "Without mentioning the word 'convert', does the convert-pdf-to-md skill trigger when a user asks you to 'summarize' or 'extract data from' a PDF file? Answer using exactly this structure:
Triggers on summarize: <yes or no>
Triggers on extract data from: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Triggers on summarize:.*yes" "Triggers on 'summarize'"
assert_contains "$output" "Triggers on extract data from:.*yes" "Triggers on 'extract data from'"
echo ""

echo "Test 2: Discipline rule (no ad-hoc parsing)..."
output=$(run_claude "According to the convert-pdf-to-md skill, is it acceptable to write ad-hoc Python code to parse a PDF's content directly instead of running the bundled script? Answer using exactly this structure:
Ad-hoc parsing acceptable: <yes or no>
Must run bundled script: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Ad-hoc parsing acceptable:.*no" "Ad-hoc parsing not acceptable"
assert_contains "$output" "Must run bundled script:.*yes" "Must run bundled script"
echo ""

echo "Test 3: Default output location..."
output=$(run_claude "According to the convert-pdf-to-md skill, where does the output folder go by default, and when should the -o flag be used? Answer using exactly this structure:
Default location: <next to source or elsewhere>
Use -o flag when: <condition>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Default location:.*next to.*source" "Default location is next to source"
assert_contains "$output" "Use -o flag when:.*explicit" "-o only on explicit user request"
echo ""

echo "Test 4: Mixed file type rule..."
output=$(run_claude "If a user references a folder containing both .pdf and .docx files, does the convert-pdf-to-md skill say to invoke sibling skills for the other file types, or only handle the .pdf files and ignore the rest?" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "convert-word-to-md" "Mentions the convert-word-to-md sibling skill"
echo ""

echo "=== All convert-pdf-to-md skill tests passed ==="
