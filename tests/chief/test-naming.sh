#!/usr/bin/env bash
# test-naming.sh - where-lines and herdr workspace labels, against the mock backend and a fake `herdr`.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-naming:"

WORK=$(mktemp -d)
harness_trap 'rm -rf "$WORK"'
mkdir -p "$WORK/project" && cd "$WORK/project" && git init -q -b master
git commit --allow-empty -q -m init
export CHIEF_HOME="$WORK/.chief"
export CHIEF_BACKEND=mock
spawn() {  # <id> [role]
  timeout 10 "$BIN/chief-spawn.sh" "$1" "$WORK/project" --mode "${2:-builder}" --branch "feat/$1" --intent "x" 2>&1
}

assert_success "spawn a task" -- spawn t-1

# where-lines (mock: no workspace)
"$BIN/chief-backlog.sh" add t-1 "Task one" >/dev/null
"$BIN/chief-backlog.sh" status t-1 in-flight >/dev/null
SHOW=$("$BIN/chief-backlog.sh" show t-1)
assert_not_contains "$SHOW" "workspace:" "mock backend has no workspace line"
assert_contains "$SHOW" "  branch: feat/t-1" "backlog show prints the branch"
assert_contains "$SHOW" "  worktree: $CHIEF_HOME/worktrees/t-1" "backlog show prints the worktree"
assert_contains "$SHOW" "  report: $CHIEF_HOME/tasks/t-1/report.md" "backlog show prints the report path"

# herdr and Orca tasks resolve their workspace name from the endpoint
mkdir -p "$CHIEF_HOME"/tasks/{old-o,x-1}
printf 'project=%s\nmode=researcher\nbranch=b\nworktree=w\nendpoint=orca:h\n' "$WORK/project" > "$CHIEF_HOME/tasks/old-o/meta"
printf 'project=%s\nmode=builder\nbranch=b\nworktree=w\nendpoint=herdr:w3:p1\n' "$WORK/project" > "$CHIEF_HOME/tasks/x-1/meta"
for id in old-o x-1; do printf '## %s [in-flight] t\n' "$id" >> "$CHIEF_HOME/backlog.md"; done
assert_contains "$("$BIN/chief-backlog.sh" show old-o)" "  workspace: old-o" "an Orca task shows its worktree name"
assert_contains "$("$BIN/chief-backlog.sh" show x-1)" "  workspace: x-1" "a herdr task shows its plain id as the workspace"

# herdr: label and cleanup
. "$BIN/lib/paths.sh"
. "$BIN/lib/meta.sh"
chief_meta_set fix-58 mode builder
chief_meta_set fix-58 project "$WORK/project"
. "$BIN/lib/backends/herdr.sh"
chief_meta_set fix-58 endpoint herdr:w1:p1
assert_contains "$(backend_attach_hint fix-58)" 'herdr workspace focus w1 (workspace "fix-58")' "the attach hint names the plain label"
CLOSED_LOG="$WORK/closed"
TASK_LABEL=
herdr() {
  local wt="$WORKTREES"
  case "$1 $2" in
    "workspace list") printf '{"result":{"workspaces":[
      {"workspace_id":"w0","label":"project","worktree":{"repo_root":"%s","checkout_path":"%s","is_linked_worktree":false}},
      {"workspace_id":"w1","label":"%s","worktree":{"repo_root":"%s","checkout_path":"%s/fix-58","is_linked_worktree":true}},
      {"workspace_id":"w2","label":"fix-58-review","worktree":{"repo_root":"%s","checkout_path":"%s/fix-58-review","is_linked_worktree":true}},
      {"workspace_id":"w3","label":"fix-580","worktree":{"repo_root":"%s","checkout_path":"%s/fix-580","is_linked_worktree":true}},
      {"workspace_id":"w4","label":"fix-58"},
      {"workspace_id":"w5","label":"fix-58 · builder · project","worktree":{"repo_root":"%s","checkout_path":"%s/other","is_linked_worktree":true}}]}}' \
      "$WORK/project" "$WORK/project" "$TASK_LABEL" "$WORK/project" "$wt" "$WORK/project" "$wt" "$WORK/project" "$wt" "$WORK/project" "$wt" ;;
    "workspace close") echo "$3" >> "$CLOSED_LOG" ;;
  esac
}
for TASK_LABEL in "fix-58" "fix-58 · builder · project"; do
  : > "$CLOSED_LOG"
  _chief_herdr_close_task_workspace fix-58
  assert_eq "$(tr '\n' ' ' < "$CLOSED_LOG")" "w1 " "cleanup closes only the task's workspace labelled '$TASK_LABEL', not look-alikes, label twins or the project's"
done

# task ids: chief_id_check and chief_id_compose
. "$BIN/lib/paths.sh"; . "$BIN/lib/meta.sh"; . "$BIN/lib/id.sh"
for ok in build-x "$(printf 'a%.0s' {1..32})"; do assert_success "id check accepts '$ok'" -- chief_id_check "$ok"; done
for bad in "$(printf 'a%.0s' {1..33})" Build-x build.x build_x "build x" 9lives; do
  assert_failure "id check rejects '$bad'" -- chief_id_check "$bad"
done
assert_contains "$(chief_id_check 'Build Foo.Bar' 2>&1)" "try 'build-foo-bar'" "id check suggests a valid id"
assert_contains "$(chief_id_check 9lives 2>&1)" "try 'lives'" "...dropping a leading digit"
assert_eq "$(chief_id_compose build-keycloak-name rv)" "build-keycloak-name-rv" "compose: base-suffix"
assert_eq "$(chief_id_compose build-dotnet-common-keycloak-by-name)" "build-dotnet-common-keycloak-by" "compose: the base is cut by whole words"
assert_eq "$(chief_id_compose build-keycloak-name rv-mastracode)" "build-keycloak-rv-mastracode" "compose: the suffix is never cut"
assert_eq "$(chief_id_compose "" rv)" "t-rv" "compose: an empty base"
assert_eq "$(chief_id_compose "$(printf 'a%.0s' {1..40})")" "$(printf 'a%.0s' {1..32})" "compose: a single long word is cut by chars"
chief_ensure_dirs
mkdir -p "$TASKS/build-a" "$ARCHIVE/build-b" "$TASKS/build-c"
printf 'mode=builder\n' > "$TASKS/build-a/meta"; printf 'mode=builder\n' > "$ARCHIVE/build-b/meta"
assert_eq "$(chief_id_compose build-a)" "build-a-2" "compose: -2 when a live task has the id"
assert_eq "$(chief_id_compose build-b)" "build-b-2" "compose: -2 when an archived task has the id"
assert_eq "$(chief_id_compose build-c)" "build-c" "compose: a meta-less folder does not count (retry reuses the id)"
cp "$TASKS/build-a/meta" "$TASKS/build-a-2.meta"; mkdir -p "$TASKS/build-a-2"; mv "$TASKS/build-a-2.meta" "$TASKS/build-a-2/meta"
assert_eq "$(chief_id_compose build-a)" "build-a-3" "compose: -3 when -2 is taken too"

harness_summary
