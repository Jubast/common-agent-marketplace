# meta.sh: the key=value read/write helpers, the task paths and the notification
# line normaliser.

setup() {
  load ../lib/common
  CHIEF_HOME="$BATS_TEST_TMPDIR/home"
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
  chief_meta_set t1 project /home/foo
  chief_meta_set t1 status spawned
  chief_meta_set t1 status working
}

@test "set: updates a key in place without duplicating it" {
  run wc -l < "$TASKS/t1/meta"
  assert_output --regexp '^ *2$'
}

@test "get: returns the latest value and untouched keys" {
  assert_equal "$(chief_meta_get t1 status)" working
  assert_equal "$(chief_meta_get t1 project)" /home/foo
}

@test "get: fails on a missing key" {
  run chief_meta_get t1 nope
  assert_failure 1
}

@test "archive: moves the task out of tasks/ and keeps its meta resolvable" {
  chief_task_archive t1
  assert_not_exist "$TASKS/t1"
  assert_file_exists "$ARCHIVE/t1/meta"
  assert_equal "$(chief_meta_get t1 status)" working
  assert_equal "$(chief_task_path t1 report.md)" "$ARCHIVE/t1/report.md"
}

@test "task_path: an unknown task points into tasks/" {
  assert_equal "$(chief_task_path t2 report.md)" "$TASKS/t2/report.md"
}

@test "exists: true for a known id, false for an unknown one" {
  chief_meta_exists t1
  run chief_meta_exists nope
  assert_failure 1
}

@test "require: returns the value when present" {
  assert_equal "$(chief_meta_require t1 status)" working
}

@test "require: names a missing key, not a false 'no meta record'" {
  run chief_meta_require t1 nope
  assert_failure 1
  assert_output --partial "missing required key"
}

@test "require: says so for a genuinely missing id" {
  run chief_meta_require nope status
  assert_output --partial "no meta record"
}

# chief_notify_line cuts the trailing metadata tags a watcher appends
notify_line_idempotent() {
  local once twice
  once=$(chief_notify_line "$1"); twice=$(chief_notify_line "$once")
  assert_equal "$twice" "$once"
}
for x in "state: done · shipped" \
         "state: done · shipped [mode: builder]" \
         "state: done · shipped [mode: builder] [agent: claude] [reviewer: r-1]" \
         "state: stale · x, no turn activity for 250s [mode: builder] [for: a]" \
         "state: done · fixed [mode: x] parser [mode: builder] [agent: claude]" \
         ""; do
  bats_test_function --description "notify_line: is idempotent on '${x:0:40}'" -- notify_line_idempotent "$x"
done

@test "notify_line: keeps a literal tag in the detail and cuts the real tags" {
  assert_equal "$(chief_notify_line "state: done · fixed [mode: x] parser [mode: builder] [agent: claude]")" \
    "state: done · fixed [mode: x] parser"
}
