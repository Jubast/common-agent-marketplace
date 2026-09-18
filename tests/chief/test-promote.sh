#!/usr/bin/env bash
# test-promote.sh - chief-promote.sh: converting a scout into a ship task in
# place (same id, same worktree, same branch), against the mock backend.
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

echo "test-promote:"

assert_failure "promote: refuses an unknown id" -- \
  "$BIN/chief-promote.sh" nope --intent "x"

assert_success "backlog: file the scout" -- "$BIN/chief-backlog.sh" add s-1 "Investigate rate limiting options"
assert_success "spawn: scout task" -- \
  timeout 10 "$BIN/chief-spawn.sh" s-1 "$WORK/project" --mode scout --intent "Investigate rate limiting options"
echo "findings: use a token bucket" > "$CHIEF_HOME/data/s-1/report.md"

SCOUT_BRIEF="$(cat "$CHIEF_HOME/data/s-1/brief.md")"
assert_not_contains "$SCOUT_BRIEF" "detached" "spawn: the scout brief no longer claims to be detached - it's on a real branch like a ship task, just never pushed or merged"
assert_contains "$SCOUT_BRIEF" "chief/s-1" "spawn: the scout brief names its actual branch"
assert_contains "$SCOUT_BRIEF" "report \`working" "spawn: the scout brief tells it to re-announce working after resuming from a terminal status"

assert_success "spawn: a ship task, to prove promote rejects non-scouts" -- \
  timeout 10 "$BIN/chief-spawn.sh" b-1 "$WORK/project" --mode ship --intent "Add hello.txt"
assert_failure "promote: refuses a ship task" -- \
  "$BIN/chief-promote.sh" b-1 --intent "x"

assert_success "promote: succeeds on the scout" -- \
  "$BIN/chief-promote.sh" s-1 --intent "Add token-bucket rate limiting" --spec "Use the existing http middleware layer"

assert_contains "$(cat "$CHIEF_HOME/state/s-1.meta")" "mode=ship" "promote: meta flips mode to ship"
assert_file_exists "$CHIEF_HOME/worktrees/s-1" "promote: same worktree still exists, nothing new was created"
assert_eq "$(git -C "$WORK/project" worktree list | grep -c 'worktrees/s-1')" "1" "promote: exactly one worktree for s-1, no duplicate"

assert_contains "$(cat "$CHIEF_HOME/data/s-1/brief.md")" "Promoted to a ship task" "promote: the notice is appended to the original brief"
assert_contains "$(cat "$CHIEF_HOME/data/s-1/brief.md")" "Add token-bucket rate limiting" "promote: the new intent is in the appended notice"
assert_contains "$(cat "$CHIEF_HOME/data/s-1/brief.md")" "Use the existing http middleware layer" "promote: the new spec is in the appended notice"

assert_contains "$(cat "$CHIEF_HOME/state/s-1.inbox/001.msg")" "Promoted to a ship task" "promote: the notice was delivered through the steering inbox"
assert_contains "$(cat "$CHIEF_HOME/state/s-1.inbox/001.msg")" "Add token-bucket rate limiting" "promote: the inbox message carries the new intent"
assert_contains "$(cat "$CHIEF_HOME/state/s-1.term.log")" "instruction waiting in" "promote: the running worker was nudged to check its inbox"

assert_contains "$("$BIN/chief-backlog.sh" show s-1)" "note: promoted from scout to ship" "promote: the backlog note records the promotion"

assert_failure "promote: refuses a task already promoted" -- \
  "$BIN/chief-promote.sh" s-1 --intent "again"

harness_summary
