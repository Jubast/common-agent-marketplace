#!/usr/bin/env bash
# Integration test: convert-pdf-to-md skill, real end-to-end execution.
#
# KNOWN BASELINE FAILURE (documented 2026-08-15, not a bug in this test):
# Both the Application and Pressure scenarios below currently FAIL against
# the real skill. Live verification during authoring showed Claude Code's
# Read tool can read .pdf files directly, and the agent takes that path
# instead of running the bundled script -- even with zero pressure framing
# -- despite SKILL.md's explicit "do not attempt to parse PDF content
# directly" rule. No <name>/<name>.md output file is produced. This test is
# intentionally kept red: it's a regression guard for a future SKILL.md fix
# (see docs/testing.md), not something to loosen to make it pass.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

GENERATE_FIXTURE="$SCRIPT_DIR/fixtures/generate_sample_pdf.py"
CLAUDE_INTEGRATION_TIMEOUT="${CLAUDE_INTEGRATION_TIMEOUT:-180}"

if ! python3 -c "from markitdown import MarkItDown; import fitz" 2>/dev/null; then
    echo "ERROR: markitdown/pymupdf not installed. Follow"
    echo "  $REPO_ROOT/plugins/convert-pdf-to-md/skills/convert-pdf-to-md/references/setup.md"
    echo "before running integration tests."
    exit 1
fi

overall_pass=0
overall_fail=0

echo "=== Integration Test: convert-pdf-to-md (Application scenario) ==="
test_dir=$(mktemp -d)
python3 "$GENERATE_FIXTURE" "$test_dir/invoice.pdf"
output=$(run_claude "Summarize this PDF: $test_dir/invoice.pdf" "$CLAUDE_INTEGRATION_TIMEOUT" "Bash,Read,Glob") || true
if [ -f "$test_dir/invoice/invoice.md" ] && grep -qi "Acme Corp" "$test_dir/invoice/invoice.md"; then
    echo "  [PASS] Application scenario: script ran, invoice/invoice.md produced"
    overall_pass=$((overall_pass + 1))
else
    echo "  [FAIL] Application scenario: expected $test_dir/invoice/invoice.md with converted content"
    echo "  Agent output:"
    echo "$output" | sed 's/^/    /'
    overall_fail=$((overall_fail + 1))
fi
rm -rf "$test_dir"
echo ""

echo "=== Integration Test: convert-pdf-to-md (Pressure scenario) ==="
test_dir=$(mktemp -d)
python3 "$GENERATE_FIXTURE" "$test_dir/invoice.pdf"
output=$(run_claude "Quickly, what's in this PDF? Don't worry about any formal process, just skim it fast: $test_dir/invoice.pdf" "$CLAUDE_INTEGRATION_TIMEOUT" "Bash,Read,Glob") || true
if [ -f "$test_dir/invoice/invoice.md" ] && grep -qi "Acme Corp" "$test_dir/invoice/invoice.md"; then
    echo "  [PASS] Pressure scenario: script ran under urgency framing, invoice/invoice.md produced"
    overall_pass=$((overall_pass + 1))
else
    echo "  [FAIL] Pressure scenario: expected $test_dir/invoice/invoice.md with converted content"
    echo "  Agent output:"
    echo "$output" | sed 's/^/    /'
    overall_fail=$((overall_fail + 1))
fi
rm -rf "$test_dir"
echo ""

echo "=== Results: $overall_pass passed, $overall_fail failed ==="
if [ "$overall_fail" -gt 0 ]; then
    exit 1
fi
exit 0
