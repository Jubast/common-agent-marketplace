#!/usr/bin/env bash
# test-crew-state.sh - chief-crew-state.sh's state classification, exercised
# directly against hand-written state/status files rather than a real spawn
# (faster, and isolates the classification logic from the spawn machinery,
# which test-lifecycle.sh already covers together).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/project" && cd "$WORK/project" && git init -q -b master
export CHIEF_HOME="$WORK/.chief"
export CHIEF_BACKEND=mock
CS="$BIN/chief-crew-state.sh"

echo "test-crew-state:"

assert_failure "refuses an unknown task id" -- "$CS" nope

# Minimal meta + a live mock terminal process, no status written yet.
mkdir -p "$CHIEF_HOME/state"
printf 'project=%s\nmode=ship\nbranch=chief/t-1\nworktree=%s\nendpoint=mock:t-1\nstatus=working\n' \
  "$WORK/project" "$WORK/.chief/worktrees/t-1" > "$CHIEF_HOME/state/t-1.meta"

( exec -a chief-mock-t-1 sleep 100000 ) >/dev/null 2>&1 &
disown
echo $! > "$CHIEF_HOME/state/t-1.term.pid"

assert_contains "$("$CS" t-1)" "state: working" "a live backend process with no status yet reads as working"
assert_contains "$("$CS" t-1)" "[mode: ship]" "the state line reports the task's mode, so Chief can tell a promoted scout from a plain one without re-reading meta by hand"

kill "$(cat "$CHIEF_HOME/state/t-1.term.pid")"
sleep 1
assert_contains "$("$CS" t-1)" "state: stale" "a dead process with no turn-ended marker reads as stale"

touch "$CHIEF_HOME/state/t-1.turn-ended"
assert_contains "$("$CS" t-1)" "state: working" "a fresh turn-ended marker reads as working even with the process dead"

touch -d "@$(($(date +%s) - 500))" "$CHIEF_HOME/state/t-1.turn-ended"
assert_contains "$("$CS" t-1)" "state: stale" "an old turn-ended marker (past the threshold) reads as stale"

echo "blocked: need operator input on limiter lib" >> "$CHIEF_HOME/state/t-1.status"
assert_contains "$("$CS" t-1)" "state: blocked · need operator input" "a blocked status line is authoritative regardless of liveness"

echo "needs-decision: pick a library" >> "$CHIEF_HOME/state/t-1.status"
assert_contains "$("$CS" t-1)" "state: needs-decision" "needs-decision status line is authoritative"

echo "failed: could not install deps" >> "$CHIEF_HOME/state/t-1.status"
assert_contains "$("$CS" t-1)" "state: failed" "failed status line is authoritative"

echo "done: added hello.txt" >> "$CHIEF_HOME/state/t-1.status"
assert_contains "$("$CS" t-1)" "state: done · added hello.txt" "done status line is authoritative and carries its detail"
assert_contains "$("$CS" t-1)" "[mode: ship]" "mode still reports correctly once the task is done"

printf 'project=%s\nmode=scout\nbranch=chief/t-2\nworktree=%s\nendpoint=mock:t-2\nstatus=working\n' \
  "$WORK/project" "$WORK/.chief/worktrees/t-2" > "$CHIEF_HOME/state/t-2.meta"
echo "done: wrote report.md" >> "$CHIEF_HOME/state/t-2.status"
assert_contains "$("$CS" t-2)" "[mode: scout]" "a scout task reports its own mode, distinct from a ship task"

harness_summary
