#!/usr/bin/env bash
# test-backend-orca.sh - exercises orca.sh's adapter functions against a REAL
# live Orca instance and a real (minimal) claude turn, on a throwaway scratch
# repo (like test-backend-herdr.sh) that backend_spawn registers with Orca
# itself and the cleanup trap unregisters again.
#
# NOT zero-cost: needs `orca` on PATH talking to a live Orca runtime, and
# spends a small number of real tokens on one trivial claude prompt. Opt in:
#
#   CHIEF_TEST_ORCA=1 bash tests/chief/test-backend-orca.sh
#
# Skips cleanly (no opt-in, no orca, no live runtime) so it's safe for
# run-tests.sh's default sweep.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
PROJECT=$(cd "$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)
. "$TEST_DIR/lib/harness.sh"

echo "test-backend-orca:"

if [ "${CHIEF_TEST_ORCA:-0}" != "1" ]; then
  echo "  (skipped - opt in with CHIEF_TEST_ORCA=1; spends real tokens and needs a live orca)"
  exit 0
fi

if ! command -v orca >/dev/null 2>&1; then
  echo "  (skipped - orca not on PATH)"
  exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "  (skipped - claude CLI not on PATH)"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "  (skipped - jq not on PATH, required by backends/orca.sh)"
  exit 0
fi

if ! orca status --json 2>/dev/null | jq -e '.ok == true' >/dev/null 2>&1; then
  echo "  (skipped - no reachable orca runtime; run 'orca open' or 'orca serve' first)"
  exit 0
fi

WORK=$(mktemp -d)
ID="chief-test-orca-$$"
ID2="$ID-b"
BRANCH="chief/$ID"
PROJECT="$WORK/chief-test-orca-proj-$$"
mkdir -p "$PROJECT" && git -C "$PROJECT" init -q -b main \
  && git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

# backend_spawn/backend_relaunch only wait for the first prompt to be accepted,
# not the turn to finish - poll backend_busy before asserting on the reply.
wait_for_idle() {  # <id> [timeout-s]
  local id=$1 timeout=${2:-60} waited=0
  while [ "$waited" -lt "$timeout" ]; do
    backend_busy "$id" || return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}
_orca_has_worktree() {  # <path> -> exit 0 if Orca still lists it
  orca worktree list --repo "path:$PROJECT" --json 2>/dev/null \
    | jq -e --arg p "$1" '[.result.worktrees[]? | select(.path == $p)] | length > 0' >/dev/null
}
_repo_id() {  # -> the scratch project's Orca repo id, empty if unregistered
  orca repo list --json 2>/dev/null \
    | jq -r --arg p "$PROJECT" '.result.repos[]? | select(.path == $p) | .id'
}
_main_wt() {  # -> the project's main worktree row
  orca worktree list --repo "path:$PROJECT" --json 2>/dev/null \
    | jq -c '.result.worktrees[]? | select(.isMainWorktree == true)'
}
_child_count() {  # -> number of worktrees nested under the project's main worktree
  _main_wt | jq -r '.childWorktreeIds | length'
}
_parent_is_main() {  # <worktree-path> -> exit 0 if its parent is the project's main worktree
  local main_id
  main_id=$(_main_wt | jq -r '.id')
  orca worktree list --repo "path:$PROJECT" --json 2>/dev/null \
    | jq -e --arg p "$1" --arg m "$main_id" '[.result.worktrees[]? | select(.path == $p and .parentWorktreeId == $m)] | length == 1' >/dev/null
}
cleanup() {
  # Everything this run could have produced, found by id/path (no meta
  # needed): terminals, worktrees, branches, then the repo registration and
  # Orca's (then empty) per-repo workspace dir.
  local repo_id wsdir
  backend_spawn_cleanup "$ID" "$PROJECT" "$BRANCH" >/dev/null 2>&1 || true
  backend_spawn_cleanup "$ID2" "$PROJECT" "chief/$ID2" >/dev/null 2>&1 || true
  wsdir=$(dirname "${WORKTREE:-}" 2>/dev/null)
  repo_id=$(_repo_id)
  [ -n "$repo_id" ] && orca project setup-delete --setup "$repo_id" >/dev/null 2>&1
  [ -n "$(_repo_id)" ] && echo "  [LEFTOVER] Orca repo registration for $PROJECT (id $(_repo_id))"
  [ -n "${WORKTREE:-}" ] && rmdir "$wsdir/.orca-worktree-trash" "$wsdir" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

export CHIEF_HOME="$WORK/.chief"
. "$CHIEF_BIN/lib/paths.sh"
. "$CHIEF_BIN/lib/meta.sh"
. "$CHIEF_BIN/lib/backends/orca.sh"

BRIEF="$WORK/brief.md"
printf 'Reply with exactly the single word: ok\n' > "$BRIEF"

SPAWN_OUTPUT=$(backend_spawn "$ID" "$PROJECT" "$BRIEF" "$BRANCH" 2>"$WORK/spawn.err")
SPAWN_RC=$?
assert_eq "$SPAWN_RC" "0" "backend_spawn succeeds"
[ "$SPAWN_RC" = "0" ] || cat "$WORK/spawn.err"

WORKTREE=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 1p)
ENDPOINT=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 2p)

[ -n "$WORKTREE" ]
assert_eq "$?" "0" "backend_spawn printed a non-empty worktree path"
assert_contains "$ENDPOINT" "orca:" "backend_spawn prints an orca: endpoint second"
assert_file_exists "$WORKTREE/.git" "backend_spawn actually created the git worktree (via orca)"

[ -n "$(_repo_id)" ]
assert_eq "$?" "0" "backend_spawn registered the unregistered scratch project with Orca"
assert_eq "$(_child_count)" "1" "the task is nested under the project's main worktree"
_parent_is_main "$WORKTREE"
assert_eq "$?" "0" "the task worktree's parent is the project's main worktree"

chief_meta_set "$ID" endpoint "$ENDPOINT"
chief_meta_set "$ID" worktree "$WORKTREE"
chief_meta_set "$ID" project "$PROJECT"

CURRENT_BRANCH=$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null)
assert_eq "$CURRENT_BRANCH" "$BRANCH" "the worktree is on the exact chief/<id> branch, renamed from Orca's own"

wait_for_idle "$ID"
CAPTURE=$(backend_capture "$ID")
assert_contains "$CAPTURE" "ok" "backend_capture shows the claude reply"
assert_contains "$CAPTURE" "bypass permissions" "backend_spawn starts the worker with bypass permissions on"

backend_busy "$ID"
assert_eq "$?" "1" "backend_busy reports idle (not busy) once the reply is done"

assert_success "backend_send delivers a special key without erroring" -- backend_send "$ID" Escape

backend_kill "$ID"
assert_eq "$?" "0" "backend_kill exits cleanly"
assert_file_exists "$WORKTREE/.git" "backend_kill does not touch the worktree"
assert_eq "$(orca terminal list --worktree "path:$WORKTREE" --json 2>/dev/null | jq -r '[.result.terminals[]?] | length')" "0" \
  "backend_kill closes every terminal in the task's worktree"

BRIEF2="$WORK/brief2.md"
printf 'Reply with exactly the single word: ok\n' > "$BRIEF2"
backend_relaunch "$ID" "$BRIEF2" 2>"$WORK/relaunch.err"
RELAUNCH_RC=$?
assert_eq "$RELAUNCH_RC" "0" "backend_relaunch succeeds in the same worktree"
[ "$RELAUNCH_RC" = "0" ] || cat "$WORK/relaunch.err"

NEW_ENDPOINT=$(chief_meta_get "$ID" endpoint)
assert_contains "$NEW_ENDPOINT" "orca:" "backend_relaunch records a fresh orca endpoint"
[ "$NEW_ENDPOINT" != "$ENDPOINT" ]
assert_eq "$?" "0" "backend_relaunch's endpoint differs from the original terminal"

wait_for_idle "$ID"
RELAUNCH_CAPTURE=$(backend_capture "$ID")
assert_contains "$RELAUNCH_CAPTURE" "ok" "backend_capture shows the relaunched claude's reply"

backend_kill "$ID"

# A second task is a second child of the same main worktree and registers the
# project only once; rolling it back leaves the first alone.
printf 'Reply with exactly the single word: ok\n' > "$WORK/brief3.md"
REPO_ID=$(_repo_id)
SPAWN2=$(backend_spawn "$ID2" "$PROJECT" "$WORK/brief3.md" "chief/$ID2" 2>/dev/null)
WORKTREE2=$(printf '%s\n' "$SPAWN2" | sed -n 1p)
assert_file_exists "$WORKTREE2/.git" "a second spawn created its worktree"
assert_eq "$(_child_count)" "2" "two tasks are two children of the main worktree"
assert_eq "$(_repo_id)" "$REPO_ID" "the project stays registered once"
backend_spawn_cleanup "$ID2" "$PROJECT" "chief/$ID2"
_orca_has_worktree "$WORKTREE2"
assert_eq "$?" "1" "backend_spawn_cleanup removes the worktree from 'orca worktree list'"
assert_file_missing "$WORKTREE2" "backend_spawn_cleanup removes the worktree from disk"
git -C "$PROJECT" show-ref --verify --quiet "refs/heads/chief/$ID2"
assert_eq "$?" "1" "backend_spawn_cleanup deletes the task's branch"
assert_eq "$(_child_count)" "1" "rolling back the second task leaves the first nested"
_parent_is_main "$WORKTREE"
assert_eq "$?" "0" "the first task is still nested under the main worktree"

backend_teardown "$ID" "$PROJECT" "$WORKTREE"
_orca_has_worktree "$WORKTREE"
assert_eq "$?" "1" "backend_teardown leaves no stale worktree entry in 'orca worktree list'"
assert_eq "$(_child_count)" "0" "no task remains nested under the main worktree"

harness_summary
