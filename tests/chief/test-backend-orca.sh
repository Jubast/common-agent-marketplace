#!/usr/bin/env bash
# test-backend-orca.sh - exercises chief-backend-orca.sh's five adapter
# functions against a REAL live Orca instance and a real (minimal) claude
# turn.
#
# NOT zero-cost: needs `orca` on PATH talking to a live Orca runtime, and
# spends a small number of real tokens on one trivial claude prompt. Opt in:
#
#   CHIEF_TEST_ORCA=1 bash tests/chief/test-backend-orca.sh
#
# Skips cleanly otherwise, so it's safe for run-tests.sh's default sweep.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
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
ID=t-orca-1
cleanup() {
  # Close whatever terminal this run produced, even on a partial failure.
  local endpoint handle
  endpoint=$(chief_meta_get "$ID" endpoint 2>/dev/null) || endpoint=""
  handle=${endpoint#orca:}
  [ -n "$handle" ] && orca terminal close --terminal "$handle" --tab >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/project" && cd "$WORK/project"
git init -q -b main
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

export CHIEF_HOME="$WORK/.chief"
. "$CHIEF_BIN/lib/chief-paths.sh"
. "$CHIEF_BIN/lib/chief-meta.sh"
. "$CHIEF_BIN/lib/chief-backend-orca.sh"

BRIEF="$WORK/brief.md"
printf 'Reply with exactly the single word: ok\n' > "$BRIEF"

SPAWN_OUTPUT=$(backend_spawn "$ID" "$WORK/project" "$BRIEF" "chief/$ID" 2>"$WORK/spawn.err")
SPAWN_RC=$?
assert_eq "$SPAWN_RC" "0" "backend_spawn succeeds"
[ "$SPAWN_RC" = "0" ] || cat "$WORK/spawn.err"

WORKTREE=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 1p)
ENDPOINT=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 2p)

assert_eq "$WORKTREE" "$WORK/.chief/worktrees/$ID" "backend_spawn prints the worktree path first"
assert_contains "$ENDPOINT" "orca:" "backend_spawn prints an orca: endpoint second"
assert_file_exists "$WORKTREE/.git" "backend_spawn actually created the git worktree"

chief_meta_set "$ID" endpoint "$ENDPOINT"
chief_meta_set "$ID" worktree "$WORKTREE"
chief_meta_set "$ID" project "$WORK/project"

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
