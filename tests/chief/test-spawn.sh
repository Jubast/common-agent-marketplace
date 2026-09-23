#!/usr/bin/env bash
# test-spawn.sh - chief-spawn.sh brief rendering, against the mock backend.
# Covers the case a plain `sed -e "s|{SPEC}|$SPEC|g"` substitution cannot
# survive: a --spec/--intent value with embedded newlines and sed-delimiter
# characters (|, &, \).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-spawn:"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/project" && cd "$WORK/project" && git init -q -b master
git commit --allow-empty -q -m init
export CHIEF_HOME="$WORK/.chief"
export CHIEF_BACKEND=mock

SPEC=$'line one with a | pipe\nline two with an & ampersand\nline three with a \\ backslash'
INTENT=$'multi-line intent\nwith a | pipe too'

assert_success "spawn: survives a --spec/--intent with embedded newlines and sed-delimiter characters" -- \
  timeout 10 "$BIN/chief-spawn.sh" t-1 "$WORK/project" --mode ship --intent "$INTENT" --spec "$SPEC"

BRIEF="$CHIEF_HOME/data/t-1/brief.md"
assert_file_exists "$BRIEF" "spawn: brief was written"
assert_contains "$(cat "$BRIEF")" "$INTENT" "spawn: the multi-line intent is rendered verbatim"
assert_contains "$(cat "$BRIEF")" "$SPEC" "spawn: the multi-line spec is rendered verbatim"
assert_not_contains "$(cat "$BRIEF")" "{TASK}" "spawn: the {TASK} placeholder was filled"
assert_not_contains "$(cat "$BRIEF")" "{SPEC}" "spawn: the {SPEC} placeholder was filled"

harness_summary
