#!/usr/bin/env bash
# test-watch.sh - chief-watch.sh's in_flight_ids against the mock backend.
# Reproduces the notification-storm bug: once a task's crew state reaches a
# terminal state and the normal flow (chief-pr-open.sh here) has acted on
# it, chief-watch.sh must stop re-notifying about it on every subsequent
# Stop hook, because in_flight_ids only follows tasks whose meta status is
# still "working".
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-watch:"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git init -q -b main "$WORK/remote.git" --bare
git clone -q "$WORK/remote.git" "$WORK/project"
( cd "$WORK/project" \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
    && git push -q origin main )

export CHIEF_HOME="$WORK/.chief"
export CHIEF_BACKEND=mock
export CHIEF_PR_PROVIDER=mock
export CHIEF_PR_MOCK_LOG="$WORK/mock.log"
export CHIEF_PR_MOCK_URL="https://example.invalid/mock/pr/1"
: > "$CHIEF_PR_MOCK_LOG"

assert_success "spawn: creates the worktree and launches the mock backend" -- \
  timeout 10 "$BIN/chief-spawn.sh" t-1 "$WORK/project" --mode ship --intent "Add hello.txt"

# Simulate the builder finishing its work and reporting done, the same way
# test-lifecycle.sh does.
(
  cd "$CHIEF_HOME/worktrees/t-1"
  echo hello > hello.txt
  git add hello.txt
  git -c user.email=t@t -c user.name=t commit -q -m "add hello.txt"
)
echo "done: added hello.txt" >> "$CHIEF_HOME/state/t-1.status"

OUT1=$(timeout 10 "$BIN/chief-watch.sh")
assert_contains "$OUT1" "t-1: state: done" "first Stop hook: watch surfaces the newly-done task"

OUT2=$(timeout 10 "$BIN/chief-watch.sh")
assert_contains "$OUT2" "t-1: state: done" \
  "second Stop hook (before anything acts on the task): watch still surfaces it - nothing has advanced its meta status yet"

# The normal flow acts on the task: open a PR for it.
"$BIN/chief-pr-open.sh" t-1 --confirm >/dev/null

OUT3=$(timeout 10 "$BIN/chief-watch.sh")
assert_not_contains "$OUT3" "t-1: state: done" \
  "third Stop hook (after chief-pr-open.sh acted on it): watch no longer re-notifies about the same already-surfaced done task"
assert_eq "$OUT3" "nothing in flight" "third Stop hook: nothing left in flight"

harness_summary
