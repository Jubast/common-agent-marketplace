#!/usr/bin/env bash
# test-teardown.sh - chief-teardown.sh's non-happy-path branches: a scout's
# unconditional discard (a scout's deliverable is its report at
# $DATA/<id>/report.md, outside the worktree - the worktree itself was
# always scratch, so there is nothing to prove "landed" before discarding
# it), and a ship's explicit --abandon override. The ordinary
# ship-refuses-then-succeeds-after-merge path is already covered end to end
# by test-lifecycle.sh; this file only covers what that one doesn't.
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

echo "test-teardown:"

# --- a scout, never landed, with a throwaway commit ---------------------
assert_success "backlog: file the scout" -- "$BIN/chief-backlog.sh" add s-1 "Investigate caching options"
assert_success "spawn: scout task" -- \
  timeout 10 "$BIN/chief-spawn.sh" s-1 "$WORK/project" --mode scout --intent "Investigate caching options"
echo "findings: use an LRU cache" > "$CHIEF_HOME/data/s-1/report.md"

# Simulate the scout doing exactly what its brief invites: a throwaway
# commit in its own scratch worktree, never meant to land.
(
  cd "$CHIEF_HOME/worktrees/s-1"
  echo scratch > scratch.txt
  git add scratch.txt
  git -c user.email=t@t -c user.name=t commit -q -m "scratch"
)
echo "done: wrote report.md" >> "$CHIEF_HOME/state/s-1.status"

assert_success "teardown: a scout tears down unconditionally, even with an unlanded commit" -- \
  "$BIN/chief-teardown.sh" s-1
assert_file_missing "$CHIEF_HOME/worktrees/s-1" "teardown: scout worktree removed"
assert_file_exists "$CHIEF_HOME/data/s-1/report.md" "teardown: the scout's report survives - it lives outside the worktree"
assert_eq "$(cat "$CHIEF_HOME/data/s-1/report.md")" "findings: use an LRU cache" "teardown: the report content is untouched"
assert_contains "$("$BIN/chief-backlog.sh" show s-1)" "[done]" "teardown: backlog item marked done"

# --- a ship, never landed, explicitly abandoned --------------------------
assert_success "backlog: file the ship" -- "$BIN/chief-backlog.sh" add b-1 "Add hello.txt"
assert_success "spawn: ship task" -- \
  timeout 10 "$BIN/chief-spawn.sh" b-1 "$WORK/project" --mode ship --intent "Add hello.txt" --spec "content: hello"
(
  cd "$CHIEF_HOME/worktrees/b-1"
  echo hello > hello.txt
  git add hello.txt
  git -c user.email=t@t -c user.name=t commit -q -m "add hello.txt"
)
echo "done: added hello.txt" >> "$CHIEF_HOME/state/b-1.status"

assert_failure "teardown: still refuses a ship with no --abandon, even after done" -- "$BIN/chief-teardown.sh" b-1
assert_file_exists "$CHIEF_HOME/worktrees/b-1" "teardown refusal: ship worktree is untouched"

assert_success "teardown: --abandon force-discards an unlanded ship" -- "$BIN/chief-teardown.sh" b-1 --abandon
assert_file_missing "$CHIEF_HOME/worktrees/b-1" "teardown --abandon: worktree removed"
assert_not_contains "$(git -C "$WORK/project" worktree list)" "worktrees/b-1" "teardown --abandon: git no longer tracks the worktree"
assert_contains "$("$BIN/chief-backlog.sh" show b-1)" "[done]" "teardown --abandon: backlog item marked done"

# --- an already-landed ship still doesn't need --abandon -----------------
assert_success "backlog: file a second ship" -- "$BIN/chief-backlog.sh" add b-2 "Add world.txt"
assert_success "spawn: second ship task" -- \
  timeout 10 "$BIN/chief-spawn.sh" b-2 "$WORK/project" --mode ship --intent "Add world.txt" --spec "content: world"
(
  cd "$CHIEF_HOME/worktrees/b-2"
  echo world > world.txt
  git add world.txt
  git -c user.email=t@t -c user.name=t commit -q -m "add world.txt"
)
"$BIN/chief-local-merge.sh" b-2 --confirm >/dev/null
assert_success "teardown: a landed ship tears down without --abandon, as before" -- "$BIN/chief-teardown.sh" b-2

# --- a squash/rebase-merged PR: the branch is never a local ancestor of --
# --- the default branch, but the provider confirms it's merged ---------
. "$BIN/lib/chief-paths.sh"
. "$BIN/lib/chief-meta.sh"

assert_success "backlog: file a third ship" -- "$BIN/chief-backlog.sh" add b-3 "Add moon.txt"
assert_success "spawn: third ship task" -- \
  timeout 10 "$BIN/chief-spawn.sh" b-3 "$WORK/project" --mode ship --intent "Add moon.txt" --spec "content: moon"
(
  cd "$CHIEF_HOME/worktrees/b-3"
  echo moon > moon.txt
  git add moon.txt
  git -c user.email=t@t -c user.name=t commit -q -m "add moon.txt"
)
chief_meta_set b-3 pr_url "https://example.invalid/mock/pr/99"
chief_meta_set b-3 pr_provider mock

assert_failure "teardown: still refuses when the recorded PR isn't reported merged" -- "$BIN/chief-teardown.sh" b-3
assert_file_exists "$CHIEF_HOME/worktrees/b-3" "teardown refusal (PR not merged): worktree is untouched"

export CHIEF_PR_MOCK_MERGED=1
assert_success "teardown: a PR the provider reports merged lands even though the branch isn't a local ancestor" -- \
  "$BIN/chief-teardown.sh" b-3
unset CHIEF_PR_MOCK_MERGED
assert_file_missing "$CHIEF_HOME/worktrees/b-3" "teardown (PR merged): worktree removed"
assert_contains "$("$BIN/chief-backlog.sh" show b-3)" "[done]" "teardown (PR merged): backlog item marked done"

harness_summary
