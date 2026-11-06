# id.sh: the task id check and how a successor's id is composed.

setup() {
  load ../lib/common
  CHIEF_HOME="$BATS_TEST_TMPDIR/home"
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
  . "$BIN/lib/id.sh"
}

@test "check: accepts ids up to 32 characters" {
  for ok in build-x "$(printf 'a%.0s' {1..32})"; do chief_id_check "$ok"; done
}

@test "check: refuses 33 characters, uppercase, . _ space and a leading digit" {
  for bad in "$(printf 'a%.0s' {1..33})" Build-x build.x build_x "build x" 9lives; do
    run -1 chief_id_check "$bad"
  done
}

@test "check: suggests a valid id" {
  run -1 chief_id_check 'Build Foo.Bar'
  assert_output --partial "try 'build-foo-bar'"
  run -1 chief_id_check 9lives
  assert_output --partial "try 'lives'"
}

@test "compose: joins base and suffix, cutting the base at a whole word" {
  assert_equal "$(chief_id_compose build-keycloak-name rv)" "build-keycloak-name-rv"
  assert_equal "$(chief_id_compose build-dotnet-common-keycloak-by-name)" "build-dotnet-common-keycloak-by"
}

@test "compose: cuts the base before the suffix, never the suffix" {
  assert_equal "$(chief_id_compose build-keycloak-name rv-mastracode)" "build-keycloak-rv-mastracode"
}

@test "compose: an empty base becomes t-<suffix>" {
  assert_equal "$(chief_id_compose "" rv)" "t-rv"
}

@test "compose: cuts a long single word at 32 characters" {
  assert_equal "$(chief_id_compose "$(printf 'a%.0s' {1..40})")" "$(printf 'a%.0s' {1..32})"
}

@test "compose: appends -2, -3 when a live or archived task has the id" {
  chief_ensure_dirs
  mkdir -p "$TASKS/build-a" "$ARCHIVE/build-b"
  printf 'mode=builder\n' > "$TASKS/build-a/meta"; printf 'mode=builder\n' > "$ARCHIVE/build-b/meta"
  assert_equal "$(chief_id_compose build-a)" "build-a-2"
  assert_equal "$(chief_id_compose build-b)" "build-b-2"
  mkdir -p "$TASKS/build-a-2"; cp "$TASKS/build-a/meta" "$TASKS/build-a-2/meta"
  assert_equal "$(chief_id_compose build-a)" "build-a-3"
}

@test "compose: a task folder without meta does not count" {
  chief_ensure_dirs
  mkdir -p "$TASKS/build-c"
  assert_equal "$(chief_id_compose build-c)" "build-c"
}
