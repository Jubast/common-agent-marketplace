#!/usr/bin/env bash
# test-backend-orca.sh - exercises chief-backend-orca.sh's five adapter
# functions against a REAL live Orca instance and a real (minimal) claude
# turn, targeting this repo itself as the project (must be an
# Orca-registered repo - see `orca repo list --json` - since Orca only
# resolves a worktree selector for one it created itself; a throwaway
# temp repo can never satisfy that, unlike test-backend-herdr.sh).
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
PROJECT="$REPO_ROOT"
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
  echo "  (skipped - jq not on PATH, required by chief-backend-orca.sh)"
  exit 0
fi

if ! orca status --json 2>/dev/null | jq -e '.ok == true' >/dev/null 2>&1; then
  echo "  (skipped - no reachable orca runtime; run 'orca open' or 'orca serve' first)"
  exit 0
fi

WORK=$(mktemp -d)
ID="chief-test-orca-$$"
BRANCH="chief/$ID"
cleanup() {
  # Best-effort: close whatever terminal this run produced, then let Orca
  # forget the worktree it made (also removes the git worktree/branch) so
  # this repo's own Orca worktree list stays clean; fall back to plain git.
  local endpoint handle worktree
  endpoint=$(chief_meta_get "$ID" endpoint 2>/dev/null) || endpoint=""
  handle=${endpoint#orca:}
  [ -n "$handle" ] && orca terminal close --terminal "$handle" --tab >/dev/null 2>&1
  worktree=$(chief_meta_get "$ID" worktree 2>/dev/null) || worktree=""
  if [ -n "$worktree" ]; then
    orca worktree rm --worktree "path:$worktree" --force >/dev/null 2>&1 \
      || { git -C "$PROJECT" worktree remove --force "$worktree" >/dev/null 2>&1
           git -C "$PROJECT" branch -D "$BRANCH" >/dev/null 2>&1; }
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

export CHIEF_HOME="$WORK/.chief"
. "$CHIEF_BIN/lib/chief-paths.sh"
. "$CHIEF_BIN/lib/chief-meta.sh"
. "$CHIEF_BIN/lib/chief-backend-orca.sh"

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

chief_meta_set "$ID" endpoint "$ENDPOINT"
chief_meta_set "$ID" worktree "$WORKTREE"
chief_meta_set "$ID" project "$PROJECT"

CURRENT_BRANCH=$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null)
assert_eq "$CURRENT_BRANCH" "$BRANCH" "the worktree is on the exact chief/<id> branch, renamed from Orca's own"

CAPTURE=$(backend_capture "$ID")
assert_contains "$CAPTURE" "ok" "backend_capture shows the claude reply"

backend_busy "$ID"
assert_eq "$?" "1" "backend_busy reports idle (not busy) once the reply is done"

assert_success "backend_send delivers a special key without erroring" -- backend_send "$ID" Escape

backend_kill "$ID"
assert_eq "$?" "0" "backend_kill exits cleanly"
assert_file_exists "$WORKTREE/.git" "backend_kill does not touch the worktree"

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

RELAUNCH_CAPTURE=$(backend_capture "$ID")
assert_contains "$RELAUNCH_CAPTURE" "ok" "backend_capture shows the relaunched claude's reply"

backend_kill "$ID"

harness_summary
