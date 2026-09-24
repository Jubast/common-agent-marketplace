#!/usr/bin/env bash
# test-spawn-cleanup.sh - chief-spawn.sh's rollback-on-failure and spawn
# lock (issue #16, item 2), exercised against the mock backend using its
# CHIEF_MOCK_SPAWN_FAIL / CHIEF_MOCK_SPAWN_MALFORMED failure injectors -
# zero cost, no herdr/orca required. Covers:
#   - backend_spawn failing outright: the worktree/branch it already
#     created get rolled back, no meta record is left behind.
#   - backend_spawn "succeeding" with malformed (one-line) output: same
#     rollback, same no-meta-record outcome.
#   - the atomic spawn lock: a same-id spawn that finds the lock already
#     held fails fast without ever touching the backend, and the lock
#     itself is always released afterwards (trap on exit).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/project" && cd "$WORK/project" && git init -q -b master
git commit --allow-empty -q -m init
export CHIEF_HOME="$WORK/.chief"
export CHIEF_BACKEND=mock

echo "test-spawn-cleanup:"

# --- backend_spawn fails outright -----------------------------------------
assert_failure \
  "spawn: fails when backend_spawn itself fails" -- \
  env CHIEF_MOCK_SPAWN_FAIL=1 "$BIN/chief-spawn.sh" t-fail "$WORK/project" \
    --mode ship --intent "should fail"

assert_file_missing "$CHIEF_HOME/worktrees/t-fail" \
  "spawn (backend_spawn failed): worktree was rolled back, not left orphaned"
assert_not_contains "$(git -C "$WORK/project" branch --list)" "chief/t-fail" \
  "spawn (backend_spawn failed): branch was rolled back, not left orphaned"
assert_file_missing "$CHIEF_HOME/state/t-fail.meta" \
  "spawn (backend_spawn failed): no meta record was left behind"

# --- backend_spawn "succeeds" but returns malformed output ----------------
assert_failure \
  "spawn: fails when backend_spawn returns malformed output" -- \
  env CHIEF_MOCK_SPAWN_MALFORMED=1 "$BIN/chief-spawn.sh" t-malformed "$WORK/project" \
    --mode ship --intent "malformed output"

assert_file_missing "$CHIEF_HOME/worktrees/t-malformed" \
  "spawn (malformed output): worktree was rolled back, not left orphaned"
assert_not_contains "$(git -C "$WORK/project" branch --list)" "chief/t-malformed" \
  "spawn (malformed output): branch was rolled back, not left orphaned"
assert_file_missing "$CHIEF_HOME/state/t-malformed.meta" \
  "spawn (malformed output): no meta record was left behind"

# --- the atomic spawn lock --------------------------------------------------
mkdir -p "$CHIEF_HOME/state"
: > "$CHIEF_HOME/state/.t-locked.spawning"

assert_failure "spawn: refuses a same-id spawn while the lock is held" -- \
  "$BIN/chief-spawn.sh" t-locked "$WORK/project" --mode ship --intent "should be locked out"

assert_file_missing "$CHIEF_HOME/worktrees/t-locked" \
  "spawn (locked): never even reached backend_spawn - no worktree created"
assert_file_missing "$CHIEF_HOME/state/t-locked.meta" \
  "spawn (locked): no meta record was left behind"

rm -f "$CHIEF_HOME/state/.t-locked.spawning"
assert_success "spawn: succeeds once the lock is released" -- \
  "$BIN/chief-spawn.sh" t-locked "$WORK/project" --mode ship --intent "should now succeed"

# --- the lock is released after both a failed and a successful spawn ------
assert_file_missing "$CHIEF_HOME/state/.t-fail.spawning" \
  "spawn: lock released via trap after a failed spawn"
assert_file_missing "$CHIEF_HOME/state/.t-locked.spawning" \
  "spawn: lock released via trap after a successful spawn"

harness_summary
