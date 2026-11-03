# lock.sh's mkdir-based mutex.

setup() {
  load lib/common
  . "$CHIEF_BIN/lib/lock.sh"
  LOCK="$BATS_TEST_TMPDIR/l1"
}

@test "the first acquire succeeds and the lock records the holder's pid" {
  run chief_lock_acquire "$LOCK" 2
  assert_success
  assert_file_exists "$LOCK/pid"
}

@test "a second acquire times out while the first still holds it" {
  chief_lock_acquire "$LOCK" 2
  run chief_lock_acquire "$LOCK" 1
  assert_failure 1
}

@test "release removes the lock directory, and acquire succeeds again" {
  chief_lock_acquire "$LOCK" 2
  chief_lock_release "$LOCK"
  assert_not_exist "$LOCK"
  run chief_lock_acquire "$LOCK" 2
  assert_success
}

@test "acquire reclaims a lock left by a dead pid" {
  mkdir "$LOCK"
  echo 999999 > "$LOCK/pid"
  run chief_lock_acquire "$LOCK" 3
  assert_success
}
