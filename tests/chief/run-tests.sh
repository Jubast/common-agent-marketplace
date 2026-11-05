#!/usr/bin/env bash
# run-tests.sh - runs every tests/chief/test-*.sh and test-*.bats and reports a summary.
#
# These are functional/integration tests of Chief's own bash scripts. The
# *.bats files run on a real herdr with a zero-cost stand-in agent; the legacy
# *.sh files mostly run against the `mock` backend (no `claude` CLI, zero tokens).
# test-backend-orca.bats runs on a real headless Orca (tag orca).
# test-backend-copilot.sh and test-backend-copilot-brief.sh are the
# exceptions: each opts into a real copilot install and a real agent turn,
# skipped by default - see this directory's README.md. Skill-BEHAVIOR tests (does Claude actually follow
# using-chief/dispatch/setup correctly) live in tests/claude-code/
# instead.
#
# Also runs every test-*.bats through the npm-pinned bats in tests/ (installed
# on first use):
#   run-tests.sh [--jobs N] [--junit DIR] [--no-orca | --only-orca] [bats args...]
# --jobs needs GNU parallel (else the run is serial); --junit writes
# DIR/report.xml; --no-orca / --only-orca split the herdr and Orca CI jobs
# (--only-orca also skips the legacy files); anything else goes to bats.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS=4
JUNIT=""
TAGS='!manual'
ONLY_ORCA=0
BATS_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs) JOBS=$2; shift 2 ;;
    --junit) JUNIT=$2; shift 2 ;;
    --no-orca) TAGS='!manual,!orca'; shift ;;
    --only-orca) TAGS='orca,!manual'; ONLY_ORCA=1; shift ;;
    *) BATS_ARGS+=("$1"); shift ;;
  esac
done

echo "========================================"
echo " Chief plugin - functional test suite"
echo "========================================"
echo ""

# Mock-backend workers (argv0 chief-mock-*) this run started are logged to
# CHIEF_MOCK_RUN_LOG by mock.sh at spawn time; any still alive after the sweep
# leaked. Other runs' workers are never in the log.
source "$SCRIPT_DIR/lib/harness.sh"
CHIEF_MOCK_RUN_LOG=$(mktemp)
export CHIEF_MOCK_RUN_LOG

total_files=0
failed_files=0

for f in "$SCRIPT_DIR"/test-*.sh; do
  [ -e "$f" ] && [ "$ONLY_ORCA" -eq 0 ] || continue
  total_files=$((total_files + 1))
  echo "--- $(basename "$f") ---"
  if ! bash "$f"; then
    failed_files=$((failed_files + 1))
  fi
  echo ""
done

bats_files=("$SCRIPT_DIR"/test-*.bats)
if [ -e "${bats_files[0]}" ]; then
  TESTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  BATS="$TESTS_DIR/node_modules/.bin/bats"
  if [ ! -x "$BATS" ] || [ "$TESTS_DIR/package-lock.json" -nt "$BATS" ]; then
    npm --prefix "$TESTS_DIR" ci --no-audit --no-fund >/dev/null || exit 1
  fi
  export BATS_LIB_PATH="$TESTS_DIR/node_modules"
  bats_cmd=("$BATS" --filter-tags "$TAGS")
  if command -v parallel >/dev/null; then
    bats_cmd+=(-j "$JOBS")
  else
    echo "warning: GNU parallel not found; running bats serially (slow)" >&2
  fi
  [ -z "$JUNIT" ] || { mkdir -p "$JUNIT"; bats_cmd+=(--report-formatter junit -o "$JUNIT"); }
  echo "--- bats ---"
  total_files=$((total_files + ${#bats_files[@]}))
  "${bats_cmd[@]}" ${BATS_ARGS[@]+"${BATS_ARGS[@]}"} "$SCRIPT_DIR" || failed_files=$((failed_files + 1))
  echo ""
fi

LEAKED_PIDS=$(harness_leaked_mock_pids "$CHIEF_MOCK_RUN_LOG")
LEAKED=$(printf '%s\n' "$LEAKED_PIDS" | grep -c .)
[ -z "$LEAKED_PIDS" ] || kill $LEAKED_PIDS 2>/dev/null
rm -f "$CHIEF_MOCK_RUN_LOG"
echo "mock workers left behind: $LEAKED"
[ "$LEAKED" -eq 0 ] || failed_files=$((failed_files + 1))

echo "========================================"
if [ "$failed_files" -eq 0 ]; then
  echo " ALL PASS ($total_files test files)"
else
  echo " $failed_files of $total_files test files had failures"
fi
echo "========================================"

[ "$failed_files" -eq 0 ]
