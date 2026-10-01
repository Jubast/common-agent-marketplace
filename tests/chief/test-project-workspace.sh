#!/usr/bin/env bash
# test-project-workspace.sh - the spawn/teardown flow against the mock
# backend: one project workspace per project (created once, reused), origin
# sync before the task worktree exists, workspace released only after the
# last active task on the project is torn down, and all Chief state under
# CHIEF_HOME - never a .chief inside a project.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-project-workspace:"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
GIT=(git -c user.email=t@t -c user.name=t)

# A workspace repo with a project checkout nested inside (as projects/<repo>),
# whose origin is ahead of the local checkout.
mkdir -p "$WORK/ws/projects" && git -C "$WORK/ws" init -q -b main
git init -q --bare -b main "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/ws/projects/app" 2>/dev/null
P="$WORK/ws/projects/app"
"${GIT[@]}" -C "$P" commit --allow-empty -q -m init && git -C "$P" push -q origin main
git clone -q "$WORK/origin.git" "$WORK/other"
echo new > "$WORK/other/from-origin.txt"
"${GIT[@]}" -C "$WORK/other" add . && "${GIT[@]}" -C "$WORK/other" commit -q -m "advance origin" && git -C "$WORK/other" push -q origin main

export CHIEF_BACKEND=mock
unset CHIEF_HOME
HOME_DIR="$WORK/ws/.chief"
KEY="$HOME_DIR/state/projects/$(printf '%s' "$P" | tr '/' '_')"

# --- spawn from inside the project: state still lands at the workspace root
cd "$P"
assert_success "spawn: first task, run with cwd inside the project" -- \
  timeout 20 "$BIN/chief-spawn.sh" a-1 "$P" --mode ship --intent "one"
assert_file_exists "$HOME_DIR/state/a-1.meta" "spawn: CHIEF_HOME resolved to the workspace root, not the project"
assert_file_missing "$P/.chief" "spawn: no .chief created inside the project"
assert_file_exists "$KEY" "spawn: the project workspace was created"
assert_file_exists "$WORK/ws/.chief/worktrees/a-1/from-origin.txt" "spawn: the worktree branches from the freshly synced origin"
assert_contains "$(cat "$KEY.log")" "chief-sync: done a-1" "spawn: the sync ran in the project workspace before the worktree"

# --- a second task on the same project reuses the workspace
assert_success "spawn: second task on the same project" -- \
  timeout 20 "$BIN/chief-spawn.sh" a-2 "$P" --mode ship --intent "two"
assert_file_exists "$KEY" "spawn: the existing project workspace is reused"
assert_contains "$(cat "$KEY.log")" "chief-sync: done a-2" "spawn: the second task syncs in the same workspace"

# --- teardown releases the workspace only after the last active task
assert_success "teardown: first task (abandoned)" -- "$BIN/chief-teardown.sh" a-1 --abandon
assert_file_missing "$WORK/ws/.chief/worktrees/a-1" "teardown: first worktree removed"
assert_file_exists "$KEY" "teardown: the project workspace stays while another task is active"
assert_success "teardown: last task (abandoned)" -- "$BIN/chief-teardown.sh" a-2 --abandon
assert_file_missing "$WORK/ws/.chief/worktrees/a-2" "teardown: last worktree removed"
assert_file_missing "$KEY" "teardown: the project workspace is released with the last task"
assert_file_missing "$P/.chief" "teardown: still no .chief inside the project"

# --- a failed spawn releases the workspace only when no other task is active
assert_failure "spawn: a failing backend_spawn" -- env CHIEF_MOCK_SPAWN_FAIL=1 timeout 20 "$BIN/chief-spawn.sh" f-1 "$P" --mode ship --intent "x"
assert_file_missing "$KEY" "failed spawn: the workspace it created is released"
assert_success "spawn: an active task" -- timeout 20 "$BIN/chief-spawn.sh" f-2 "$P" --mode ship --intent "y"
assert_failure "spawn: a failing backend_spawn beside it" -- env CHIEF_MOCK_SPAWN_FAIL=1 timeout 20 "$BIN/chief-spawn.sh" f-3 "$P" --mode ship --intent "z"
assert_file_exists "$KEY" "failed spawn: the workspace stays while another task is active"
"$BIN/chief-teardown.sh" f-2 --abandon >/dev/null 2>&1

# --- default CHIEF_HOME resolution from a project and from its worktree
assert_success "spawn: a task to resolve from" -- timeout 20 "$BIN/chief-spawn.sh" b-1 "$P" --mode ship --intent "three"
for dir in "$P" "$WORK/ws/.chief/worktrees/b-1"; do
  assert_success "backlog from ${dir#"$WORK"/}" -- bash -c "cd '$dir' && '$BIN/chief-backlog.sh' add x-$RANDOM t"
  assert_file_missing "$dir/.chief" "no .chief created in ${dir#"$WORK"/}"
done
"$BIN/chief-teardown.sh" b-1 --abandon >/dev/null 2>&1

harness_summary
