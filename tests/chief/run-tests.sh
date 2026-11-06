#!/usr/bin/env bash
# run-tests.sh - runs every .bats under tests/chief/{unit,workflow,backends,harness}
# through the npm-pinned bats in tests/ (installed on first use) and reports a summary.
#
# These are functional/integration tests of Chief's own bash scripts, run on a
# real herdr or a real headless Orca with a zero-cost stand-in agent. Tests
# that spend real tokens live in manual/ and are never run here. Skill-BEHAVIOR
# tests (does Claude actually follow using-chief/dispatch/setup correctly) live
# in tests/claude-code/ instead.
#
#   run-tests.sh [--jobs N] [--junit DIR] [--no-orca | --only-orca] [bats args...] [path...]
# --jobs needs GNU parallel (else the run is serial); --junit writes
# DIR/report.xml; --no-orca / --only-orca split the herdr and Orca CI jobs;
# a path (a folder or .bats file, e.g. tests/chief/unit) replaces the default of
# the whole suite; other args go to bats.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BATS="$TESTS_DIR/node_modules/.bin/bats"
JOBS=4
JUNIT=""
TAGS=''
BATS_ARGS=()
PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs) JOBS=$2; shift 2 ;;
    --junit) JUNIT=$2; shift 2 ;;
    --no-orca) TAGS='!orca'; shift ;;
    --only-orca) TAGS='orca'; shift ;;
    *.bats) PATHS+=("$1"); shift ;;
    -*) BATS_ARGS+=("$1"); shift ;;
    *) if [ -d "$1" ]; then PATHS+=("$1"); else BATS_ARGS+=("$1"); fi; shift ;;
  esac
done

if [ ! -x "$BATS" ] || [ "$TESTS_DIR/package-lock.json" -nt "$BATS" ]; then
  npm --prefix "$TESTS_DIR" ci --no-audit --no-fund >/dev/null || exit 1
fi
export BATS_LIB_PATH="$TESTS_DIR/node_modules"
export BATS_TEST_TIMEOUT=300  # the slowest test takes about 45 s; a hang must not last until the job limit
bats_cmd=("$BATS" -r --setup-suite-file "$SCRIPT_DIR/setup_suite.bash")
[ -z "$TAGS" ] || bats_cmd+=(--filter-tags "$TAGS")
if command -v parallel >/dev/null; then
  bats_cmd+=(-j "$JOBS")
else
  echo "warning: GNU parallel not found; running bats serially (slow)" >&2
fi
[ -z "$JUNIT" ] || { mkdir -p "$JUNIT"; bats_cmd+=(--report-formatter junit -o "$JUNIT"); }

echo "========================================"
echo " Chief plugin - functional test suite"
echo "========================================"
if "${bats_cmd[@]}" ${BATS_ARGS[@]+"${BATS_ARGS[@]}"} "${PATHS[@]-$SCRIPT_DIR}"; then
  echo " ALL PASS"
else
  echo " FAILURES"
  exit 1
fi
