# Where-lines, herdr workspace labels and their cleanup (on a real herdr), and
# task ids.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
  . "$BIN/lib/id.sh"
}

teardown() { chief_herdr_stop; }

# workspaces - "label|checkout-path" per herdr workspace
workspaces() { herdr workspace list | jq -r '.result.workspaces[] | "\(.label)|\(.worktree.checkout_path // "")"'; }

@test "backlog show prints the branch, worktree, report path and the workspace of a spawned task" {
  spawn t-1
  "$BIN/chief-backlog.sh" add t-1 "Task one" >/dev/null
  "$BIN/chief-backlog.sh" status t-1 in-flight >/dev/null
  run "$BIN/chief-backlog.sh" show t-1
  assert_output --partial "  branch: feat/t-1"
  assert_output --partial "  worktree: $CHIEF_HOME/worktrees/t-1"
  assert_output --partial "  report: $CHIEF_HOME/tasks/t-1/report.md"
  assert_output --partial "  workspace: t-1"
}

@test "herdr and Orca tasks resolve their workspace name from the endpoint" {
  mkdir -p "$CHIEF_HOME"/tasks/{old-o,x-1}
  printf 'project=%s\nmode=researcher\nbranch=b\nworktree=w\nendpoint=orca:h\n' "$WORK/project" > "$CHIEF_HOME/tasks/old-o/meta"
  printf 'project=%s\nmode=builder\nbranch=b\nworktree=w\nendpoint=herdr:w3:p1\n' "$WORK/project" > "$CHIEF_HOME/tasks/x-1/meta"
  for id in old-o x-1; do printf '## %s [in-flight] t\n' "$id" >> "$CHIEF_HOME/backlog.md"; done
  run "$BIN/chief-backlog.sh" show old-o
  assert_output --partial "  workspace: old-o"
  run "$BIN/chief-backlog.sh" show x-1
  assert_output --partial "  workspace: x-1"
}

@test "the attach hint names the plain label" {
  . "$BIN/lib/backends/herdr.sh"
  chief_meta_set fix-58 endpoint herdr:w1:p1
  assert_equal "$(backend_attach_hint fix-58)" 'herdr workspace focus w1 (workspace "fix-58")'
}

# cleanup_closes_only <label of the task's workspace>
cleanup_closes_only() {
  . "$BIN/lib/backends/herdr.sh"
  spawn fix-58
  spawn fix-580
  herdr workspace create --cwd "$WORK" --label fix-58 >/dev/null   # a label twin with no worktree
  [ "$1" = fix-58 ] || herdr workspace rename "$(herdr workspace list | jq -r '.result.workspaces[] | select(.worktree.checkout_path == "'"$WORKTREES/fix-58"'") | .workspace_id')" "$1" >/dev/null
  _chief_herdr_close_task_workspace fix-58
  run workspaces
  refute_line --regexp "\\|$WORKTREES/fix-58\$"
  assert_line "fix-580|$WORKTREES/fix-580"
  assert_line "fix-58|"   # the twin survives
  assert_line "project|$WORK/project"
}
for label in "fix-58" "fix-58 · builder · project"; do
  bats_test_function --description "cleanup closes only the task's workspace labelled '$label', not look-alikes, label twins or the project's" \
    -- cleanup_closes_only "$label"
done

@test "id check accepts valid ids and suggests a valid one for invalid ids" {
  for ok in build-x "$(printf 'a%.0s' {1..32})"; do chief_id_check "$ok"; done
  for bad in "$(printf 'a%.0s' {1..33})" Build-x build.x build_x "build x" 9lives; do
    run chief_id_check "$bad"
    assert_failure
  done
  run chief_id_check 'Build Foo.Bar'
  assert_output --partial "try 'build-foo-bar'"
  run chief_id_check 9lives
  assert_output --partial "try 'lives'"
}

@test "id compose: base-suffix, whole-word cuts, an uncut suffix, empty base, long words" {
  assert_equal "$(chief_id_compose build-keycloak-name rv)" "build-keycloak-name-rv"
  assert_equal "$(chief_id_compose build-dotnet-common-keycloak-by-name)" "build-dotnet-common-keycloak-by"
  assert_equal "$(chief_id_compose build-keycloak-name rv-mastracode)" "build-keycloak-rv-mastracode"
  assert_equal "$(chief_id_compose "" rv)" "t-rv"
  assert_equal "$(chief_id_compose "$(printf 'a%.0s' {1..40})")" "$(printf 'a%.0s' {1..32})"
}

@test "id compose: -2/-3 when a live or archived task has the id; a meta-less folder does not count" {
  chief_ensure_dirs
  mkdir -p "$TASKS/build-a" "$ARCHIVE/build-b" "$TASKS/build-c"
  printf 'mode=builder\n' > "$TASKS/build-a/meta"; printf 'mode=builder\n' > "$ARCHIVE/build-b/meta"
  assert_equal "$(chief_id_compose build-a)" "build-a-2"
  assert_equal "$(chief_id_compose build-b)" "build-b-2"
  assert_equal "$(chief_id_compose build-c)" "build-c"
  mkdir -p "$TASKS/build-a-2"; cp "$TASKS/build-a/meta" "$TASKS/build-a-2/meta"
  assert_equal "$(chief_id_compose build-a)" "build-a-3"
}
