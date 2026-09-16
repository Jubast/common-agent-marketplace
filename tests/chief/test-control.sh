#!/usr/bin/env bash
# test-control.sh - chief-control.sh: interrupt | exit | relaunch.
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
CTL="$BIN/chief-control.sh"
META_LIB="$BIN/lib/chief-meta.sh"

echo "test-control:"

assert_failure "refuses an unknown task id" -- "$CTL" nope interrupt

timeout 10 "$BIN/chief-spawn.sh" t-1 "$WORK/project" --mode ship --intent "test" --spec "test" >/dev/null

assert_failure "refuses an unknown verb" -- "$CTL" t-1 bogus

old_pid=$(cat "$CHIEF_HOME/state/t-1.term.pid")
assert_success "interrupt succeeds" -- "$CTL" t-1 interrupt
assert_contains "$(cat "$CHIEF_HOME/state/t-1.term.log")" "send: Escape" "interrupt delivers Escape to the backend"
kill -0 "$old_pid" 2>/dev/null
assert_eq "$?" "0" "interrupt does NOT stop the agent - it keeps running"

assert_success "exit succeeds" -- "$CTL" t-1 exit
kill -0 "$old_pid" 2>/dev/null
assert_eq "$?" "1" "exit stops the agent process"
assert_file_exists "$CHIEF_HOME/worktrees/t-1" "exit preserves the worktree"
TASK_STATUS=$(. "$META_LIB"; STATE="$CHIEF_HOME/state"; chief_meta_get t-1 status)
assert_eq "$TASK_STATUS" "exited" "exit records status=exited"

assert_failure "relaunch without --note is refused" -- "$CTL" t-1 relaunch

assert_success "relaunch with --note succeeds" -- "$CTL" t-1 relaunch --note "was mid-way adding hello.txt"
assert_contains "$(tail -6 "$WORK/.chief/data/t-1/brief.md")" "was mid-way adding hello.txt" "the checkpoint note is appended to the brief"
assert_contains "$(tail -6 "$WORK/.chief/data/t-1/brief.md")" "Relaunch checkpoint" "the checkpoint section is clearly marked"
new_pid=$(cat "$CHIEF_HOME/state/t-1.term.pid")
kill -0 "$new_pid" 2>/dev/null
assert_eq "$?" "0" "relaunch starts a new backend process in the same worktree"
TASK_STATUS2=$(. "$META_LIB"; STATE="$CHIEF_HOME/state"; chief_meta_get t-1 status)
assert_eq "$TASK_STATUS2" "working" "relaunch records status=working again"

harness_summary
