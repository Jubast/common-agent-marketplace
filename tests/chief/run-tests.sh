#!/usr/bin/env bash
# run-tests.sh - runs every tests/chief/test-*.sh and reports a summary.
#
# These are functional/integration tests of Chief's own bash scripts. All of
# them run against the `mock` backend (no `claude` CLI invocation, zero
# model tokens) EXCEPT test-backend-herdr.sh, which opts into a real herdr
# install and a real (trivial) claude turn and is skipped by default - see
# this directory's README.md. Skill-BEHAVIOR tests (does Claude actually
# follow using-chief/dispatch/reviewer/setup correctly) live in
# tests/claude-code/ instead, and the Orca backend adapter is still an
# unverified draft - see chief-backend-orca.sh's own header.
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
