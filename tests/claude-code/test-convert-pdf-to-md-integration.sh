#!/usr/bin/env bash
# Integration test: convert-pdf-to-md skill, real end-to-end execution.
#
# Both scenarios failed until SKILL.md named the Read tool as off-limits on
# the .pdf (fixed 2026-08-20, see docs/testing.md); they are regression guards.
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
