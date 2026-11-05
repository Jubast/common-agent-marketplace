# meta.sh's key=value read/write helpers.

setup() {
  load ../lib/common
  CHIEF_HOME="$BATS_TEST_TMPDIR/home"
  . "$CHIEF_BIN/lib/paths.sh"
  . "$CHIEF_BIN/lib/meta.sh"
  chief_meta_set t1 project /home/foo
  chief_meta_set t1 status spawned
  chief_meta_set t1 status working
}

@test "set() upserts in place, does not duplicate the key" {
  run wc -l < "$TASKS/t1/meta"
  assert_output --regexp '^ *2$'
}

@test "get() returns the latest value and untouched keys" {
  assert_equal "$(chief_meta_get t1 status)" working
  assert_equal "$(chief_meta_get t1 project)" /home/foo
}

@test "get() on a missing key returns exit 1" {
  run chief_meta_get t1 nope
  assert_failure 1
}

@test "archive moves the folder out of tasks/ and keeps the meta resolvable" {
  chief_task_archive t1
  assert_not_exist "$TASKS/t1"
  assert_file_exists "$ARCHIVE/t1/meta"
  assert_equal "$(chief_meta_get t1 status)" working
  assert_equal "$(chief_task_path t1 report.md)" "$ARCHIVE/t1/report.md"
}

@test "paths of an unknown task point into tasks/" {
  assert_equal "$(chief_task_path t2 report.md)" "$TASKS/t2/report.md"
}

@test "exists() is true for a known id and false for an unknown one" {
  chief_meta_exists t1
  run chief_meta_exists nope
  assert_failure
}

@test "require() returns the value when present" {
  assert_equal "$(chief_meta_require t1 status)" working
}

@test "require() names a missing key, not a false 'no meta record'" {
  run chief_meta_require t1 nope
  assert_failure 1
  assert_output --partial "missing required key"
}

@test "require() on a genuinely missing id says so" {
  run chief_meta_require nope status
  assert_output --partial "no meta record"
}
