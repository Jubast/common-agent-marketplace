#!/usr/bin/env bash
# test-lock.sh - chief-lock.sh's mkdir-based mutex.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
. "$CHIEF_BIN/lib/chief-lock.sh"

echo "test-lock:"

LOCK="$WORK/l1"
chief_lock_acquire "$LOCK" 2
assert_eq "$?" "0" "first acquire succeeds"
assert_file_exists "$LOCK/pid" "the lock directory records the holder's pid"

( chief_lock_acquire "$LOCK" 1 )
assert_eq "$?" "1" "a second acquire times out while the first still holds it"

chief_lock_release "$LOCK"
assert_file_missing "$LOCK" "release removes the lock directory"

chief_lock_acquire "$LOCK" 2
assert_eq "$?" "0" "acquire succeeds again after release"
chief_lock_release "$LOCK"

mkdir "$LOCK"
echo 999999 > "$LOCK/pid"
chief_lock_acquire "$LOCK" 3
assert_eq "$?" "0" "acquire reclaims a lock left by a dead pid"
chief_lock_release "$LOCK"

harness_summary
