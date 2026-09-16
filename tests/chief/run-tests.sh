#!/usr/bin/env bash
# run-tests.sh - runs every tests/chief/test-*.sh and reports a summary.
#
# These are functional/integration tests of Chief's own bash scripts. Most
# run against the `mock` backend (no `claude` CLI, zero tokens).
# test-backend-orca-mock.sh is also zero-cost - it unit-tests
# chief-backend-orca.sh against a fake `orca` CLI. test-backend-herdr.sh and
# test-backend-orca.sh are the exceptions: each opts into a real
# herdr/orca install and a real claude turn, skipped by default - see this
# directory's README.md. Skill-BEHAVIOR tests (does Claude actually follow
# using-chief/dispatch/reviewer/setup correctly) live in tests/claude-code/
# instead.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo " Chief plugin - functional test suite"
echo "========================================"
echo ""

total_files=0
failed_files=0

for f in "$SCRIPT_DIR"/test-*.sh; do
  [ -e "$f" ] || continue
  total_files=$((total_files + 1))
  echo "--- $(basename "$f") ---"
  if ! bash "$f"; then
    failed_files=$((failed_files + 1))
  fi
  echo ""
done

echo "========================================"
if [ "$failed_files" -eq 0 ]; then
  echo " ALL PASS ($total_files test files)"
else
  echo " $failed_files of $total_files test files had failures"
fi
echo "========================================"

[ "$failed_files" -eq 0 ]
