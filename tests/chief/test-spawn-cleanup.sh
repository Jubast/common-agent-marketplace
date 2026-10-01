#!/usr/bin/env bash
# test-spawn-cleanup.sh - chief-spawn.sh's rollback-on-failure and spawn
# lock (issue #16, item 2), exercised against the mock backend using its
# CHIEF_MOCK_SPAWN_FAIL / CHIEF_MOCK_SPAWN_MALFORMED failure injectors -
# zero cost, no herdr/orca required. Covers:
#   - a missing --branch: fails with nothing left behind.
#   - backend_spawn failing outright: the worktree/branch it already
#     created get rolled back, no meta record is left behind.
#   - backend_spawn "succeeding" with malformed (one-line) output: same
#     rollback, same no-meta-record outcome.
#   - a stub status=spawning meta (a spawn interrupted mid-flight, issue
#     #36): crew-state reports it blocked, watch surfaces it, and
#     teardown --abandon cleans it up.
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

# --- a missing --branch fails before anything is created -------------------
assert_failure "spawn: fails without --branch" -- \
  "$BIN/chief-spawn.sh" t-nobranch "$WORK/project" --mode ship --intent "no branch"

assert_file_missing "$CHIEF_HOME/worktrees/t-nobranch" \
  "spawn (no --branch): no worktree created"
assert_file_missing "$CHIEF_HOME/state/t-nobranch.meta" \
  "spawn (no --branch): no meta record left behind"
assert_file_missing "$CHIEF_HOME/state/t-nobranch.status" \
  "spawn (no --branch): no state files left behind"
assert_file_missing "$CHIEF_HOME/state/.t-nobranch.spawning" \
  "spawn (no --branch): no lock left behind"
assert_eq "$(git -C "$WORK/project" branch --list | wc -l | tr -d ' ')" "1" \
  "spawn (no --branch): no branch created"

# --- backend_spawn fails outright -----------------------------------------
assert_failure \
  "spawn: fails when backend_spawn itself fails" -- \
  env CHIEF_MOCK_SPAWN_FAIL=1 "$BIN/chief-spawn.sh" t-fail "$WORK/project" \
    --mode ship --branch feat/t-fail --intent "should fail"

assert_file_missing "$CHIEF_HOME/worktrees/t-fail" \
  "spawn (backend_spawn failed): worktree was rolled back, not left orphaned"
assert_not_contains "$(git -C "$WORK/project" branch --list)" "feat/t-fail" \
  "spawn (backend_spawn failed): branch was rolled back, not left orphaned"
assert_file_missing "$CHIEF_HOME/state/t-fail.meta" \
  "spawn (backend_spawn failed): no meta record was left behind"

# --- backend_spawn "succeeds" but returns malformed output ----------------
assert_failure \
  "spawn: fails when backend_spawn returns malformed output" -- \
  env CHIEF_MOCK_SPAWN_MALFORMED=1 "$BIN/chief-spawn.sh" t-malformed "$WORK/project" \
    --mode ship --branch feat/t-malformed --intent "malformed output"

assert_file_missing "$CHIEF_HOME/worktrees/t-malformed" \
  "spawn (malformed output): worktree was rolled back, not left orphaned"
assert_not_contains "$(git -C "$WORK/project" branch --list)" "feat/t-malformed" \
  "spawn (malformed output): branch was rolled back, not left orphaned"
assert_file_missing "$CHIEF_HOME/state/t-malformed.meta" \
  "spawn (malformed output): no meta record was left behind"

# --- an interrupted spawn leaves a status=spawning stub -------------------
mkdir -p "$CHIEF_HOME/state"
printf 'project=%s\nmode=ship\nbranch=chief/t-stub\nworktree=%s\nstatus=spawning\n' \
  "$WORK/project" "$CHIEF_HOME/worktrees/t-stub" > "$CHIEF_HOME/state/t-stub.meta"

assert_contains "$("$BIN/task/chief-crew-state.sh" t-stub)" "state: blocked" \
  "crew-state: a spawning stub is reported blocked"
assert_contains "$(timeout 10 "$BIN/chief-watch.sh")" "t-stub: state: blocked" \
  "watch: surfaces the spawning stub"
: > "$CHIEF_HOME/state/.t-stub.spawning"
assert_contains "$("$BIN/task/chief-crew-state.sh" t-stub)" "state: working" \
  "crew-state: a spawning stub with the spawn lock held is a live spawn, not blocked"
rm -f "$CHIEF_HOME/state/.t-stub.spawning"
assert_success "teardown: --abandon cleans up the spawning stub" -- \
  "$BIN/chief-teardown.sh" t-stub --abandon
assert_contains "$(cat "$CHIEF_HOME/state/t-stub.meta")" "status=torn-down" \
  "teardown: the stub is marked torn-down"

# --- the atomic spawn lock --------------------------------------------------
mkdir -p "$CHIEF_HOME/state"
: > "$CHIEF_HOME/state/.t-locked.spawning"

assert_failure "spawn: refuses a same-id spawn while the lock is held" -- \
  "$BIN/chief-spawn.sh" t-locked "$WORK/project" --mode ship --branch feat/t-locked --intent "should be locked out"

assert_file_missing "$CHIEF_HOME/worktrees/t-locked" \
  "spawn (locked): never even reached backend_spawn - no worktree created"
assert_file_missing "$CHIEF_HOME/state/t-locked.meta" \
  "spawn (locked): no meta record was left behind"

rm -f "$CHIEF_HOME/state/.t-locked.spawning"
assert_success "spawn: succeeds once the lock is released" -- \
  "$BIN/chief-spawn.sh" t-locked "$WORK/project" --mode ship --branch feat/t-locked --intent "should now succeed"

# --- the lock is released after both a failed and a successful spawn ------
assert_file_missing "$CHIEF_HOME/state/.t-fail.spawning" \
  "spawn: lock released via trap after a failed spawn"
assert_file_missing "$CHIEF_HOME/state/.t-locked.spawning" \
  "spawn: lock released via trap after a successful spawn"

harness_summary
