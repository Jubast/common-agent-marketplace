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

# an Orca task resolves its workspace name from its endpoint
mkdir -p "$CHIEF_HOME"/tasks/{old-o,x-1}
printf 'project=%s\nmode=researcher\nbranch=b\nworktree=w\nendpoint=orca:h\n' "$WORK/project" > "$CHIEF_HOME/tasks/old-o/meta"
printf 'project=%s\nmode=builder\nbranch=b\nworktree=w\nendpoint=herdr:w3:p1\nlabel=x-1 · builder · project\n' "$WORK/project" > "$CHIEF_HOME/tasks/x-1/meta"
for id in old-o x-1; do printf '## %s [in-flight] t\n' "$id" >> "$CHIEF_HOME/backlog.md"; done
assert_contains "$("$BIN/chief-backlog.sh" show old-o)" "  workspace: old-o" "an Orca task shows its worktree name"
assert_contains "$("$BIN/chief-backlog.sh" show x-1)" "  workspace: x-1 · builder · project" "a recorded label is shown"

# herdr: new label, and cleanup finds both label forms
. "$BIN/lib/paths.sh"
. "$BIN/lib/meta.sh"
chief_meta_set fix-58 mode builder
chief_meta_set fix-58 project "$WORK/project"
. "$BIN/lib/backends/herdr.sh"
assert_eq "$(_chief_herdr_label fix-58)" "fix-58 · builder · project" "herdr label is <id> · <role> · <project>"
CLOSED_LOG="$WORK/closed"
herdr() {
  case "$1 $2" in
    "workspace list") printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"fix-58 · builder · project"},{"workspace_id":"w2","label":"chief-fix-58"},{"workspace_id":"w3","label":"fix-58-review · reviewer · project"},{"workspace_id":"w4","label":"chief-fix-580"}]}}' ;;
    "workspace close") echo "$3" >> "$CLOSED_LOG" ;;
  esac
}
_chief_herdr_close_task_workspace fix-58
assert_eq "$(tr '\n' ' ' < "$CLOSED_LOG")" "w1 w2 " "cleanup closes the new and the older label, not another task's"

harness_summary
