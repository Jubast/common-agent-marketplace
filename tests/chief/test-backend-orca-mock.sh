#!/usr/bin/env bash
# test-backend-orca-mock.sh - zero-cost unit test of orca.sh's
# argument-building and JSON-parsing, against a FAKE `orca` CLI stub (see
# below). No real Orca instance, no claude turn, no tokens.
#
# Not a substitute for test-backend-orca.sh (the opt-in real-Orca
# integration test): this only proves the adapter calls `orca` the way it
# claims to, against canned responses shaped like the real CLI's output.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-backend-orca-mock:"

if ! command -v jq >/dev/null 2>&1; then
  echo "  (skipped - jq not on PATH, required by backends/orca.sh)"
  exit 0
fi

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/project" "$WORK/bin"
( cd "$WORK/project" && git init -q -b main \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )

# --- fake `orca` -------------------------------------------------------
# Logs every call to $ORCA_MOCK_LOG and returns canned --json responses.
# `terminal wait --for tui-idle` exits 0 (idle) unless $ORCA_MOCK_BUSY=1.
# `worktree create` does a real `git worktree add` (sanitizing '/' out of
# --name into the branch, like the real Orca does) so backend_spawn's
# branch rename has something real to act on; fails instead with
# $ORCA_MOCK_WT_FAIL=1, for the "project isn't Orca-known" path.
# `worktree list`/`rm` mirror that against the real git worktrees under
# $ORCA_MOCK_WORKTREES. `terminal send` fails with $ORCA_MOCK_SEND_FAIL=1.
cat > "$WORK/bin/orca" <<'FAKE_ORCA'
#!/usr/bin/env bash
echo "$*" >> "$ORCA_MOCK_LOG"
# Real orca prints a connect banner to stderr on every call - mirror that
# so a regression to 2>&1 (merging it into a --json capture, breaking jq)
# fails loud instead of silently passing.
echo "[relay-connect] Handshake OK at version=mock" >&2
case "$1 $2" in
  "worktree create")
    if [ "${ORCA_MOCK_WT_FAIL:-0}" = "1" ]; then
      echo '{"ok":false,"error":{"code":"runtime_error","message":"Not a valid git repository"}}'
      exit 1
    fi
    repo_path="${4#path:}"
    sanitized=${6//\//-}
    new_path="$ORCA_MOCK_WORKTREES/$sanitized"
    git -C "$repo_path" worktree add -q -b "$sanitized" "$new_path" >&2 || exit 1
    printf '{"ok":true,"result":{"worktree":{"path":"%s","branch":"refs/heads/%s"}}}\n' "$new_path" "$sanitized"
    ;;
  "terminal create")
    echo '{"ok":true,"result":{"terminal":{"handle":"term_mock-1"}}}'
    ;;
  "terminal wait")
    if [ "${ORCA_MOCK_BUSY:-0}" = "1" ]; then
      echo '{"ok":false,"error":{"code":"timeout"}}'
      exit 1
    fi
    echo '{"ok":true}'
    ;;
  "terminal read")
    echo '{"ok":true,"result":{"terminal":{"tail":["line one","line two"]}}}'
    ;;
  "terminal send")
    if [ "${ORCA_MOCK_SEND_FAIL:-0}" = "1" ]; then
      echo '{"ok":false,"error":{"code":"runtime_error"}}'
      exit 1
    fi
    echo '{"ok":true}'
    ;;
  "worktree list")
    repo_path="${4#path:}"
    git -C "$repo_path" worktree list --porcelain | awk -v root="$ORCA_MOCK_WORKTREES/" '
      /^worktree / { path = substr($0, 10) }
      /^branch /   { if (index(path, root) == 1) printf "{\"path\":\"%s\",\"branch\":\"%s\"}\n", path, substr($0, 8) }' \
      | jq -sc '{ok:true,result:{worktrees:.}}'
    ;;
  "worktree rm")
    wt="${4#path:}"
    common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir) || exit 1
    git -C "$common/.." worktree remove --force "$wt" || exit 1
    echo '{"ok":true}'
    ;;
  "terminal close")
    echo '{"ok":true}'
    ;;
  *)
    echo "fake-orca: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
FAKE_ORCA
chmod +x "$WORK/bin/orca"
export PATH="$WORK/bin:$PATH"
export ORCA_MOCK_LOG="$WORK/orca.log"
export ORCA_MOCK_WORKTREES="$WORK/orca-worktrees"
mkdir -p "$ORCA_MOCK_WORKTREES"
: > "$ORCA_MOCK_LOG"

export CHIEF_HOME="$WORK/.chief"
. "$CHIEF_BIN/lib/paths.sh"
. "$CHIEF_BIN/lib/meta.sh"
. "$CHIEF_BIN/lib/backends/orca.sh"

ID=t-orca-1
BRANCH="chief/$ID"
BRIEF="$WORK/brief.md"
printf 'Reply with exactly the single word: ok\n' > "$BRIEF"

SPAWN_OUTPUT=$(backend_spawn "$ID" "$WORK/project" "$BRIEF" "$BRANCH" 2>"$WORK/spawn.err")
SPAWN_RC=$?
assert_eq "$SPAWN_RC" "0" "backend_spawn succeeds"
[ "$SPAWN_RC" = "0" ] || cat "$WORK/spawn.err"

WORKTREE=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 1p)
ENDPOINT=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 2p)

assert_eq "$WORKTREE" "$ORCA_MOCK_WORKTREES/$ID" "backend_spawn prints the worktree path Orca assigned"
assert_eq "$ENDPOINT" "orca:term_mock-1" "backend_spawn prints an orca:<handle> endpoint second"
assert_file_exists "$WORKTREE/.git" "orca worktree create actually created a real git worktree"

CURRENT_BRANCH=$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)
assert_eq "$CURRENT_BRANCH" "$BRANCH" "backend_spawn renamed Orca's sanitized branch to the requested chief/<id> branch"

assert_contains "$(cat "$ORCA_MOCK_LOG")" "worktree create --repo path:$WORK/project --name $ID --no-parent --json" \
  "backend_spawn calls 'orca worktree create' scoped to the project repo, not a raw git worktree add"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal create --worktree path:$WORKTREE --command claude --dangerously-skip-permissions --json" \
  "backend_spawn launches claude in bypass-permissions mode in the worktree path Orca just made"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal send --terminal term_mock-1 --text Reply with exactly the single word: ok" \
  "backend_spawn submits the brief's own content as the first prompt (not a path)"

: > "$ORCA_MOCK_LOG"
ORCA_MOCK_WT_FAIL=1 backend_spawn "t-orca-fail" "$WORK/project" "$BRIEF" "chief/t-orca-fail" 2>"$WORK/spawn-fail.err"
assert_eq "$?" "1" "backend_spawn fails when 'orca worktree create' fails"
assert_contains "$(cat "$WORK/spawn-fail.err")" "orca worktree create" \
  "backend_spawn's failure message names the failing orca command"
assert_contains "$(cat "$WORK/spawn-fail.err")" "Orca-registered repo" \
  "backend_spawn's failure message hints that the project needs to be Orca-registered"

chief_meta_set "$ID" endpoint "$ENDPOINT"
chief_meta_set "$ID" worktree "$WORKTREE"
chief_meta_set "$ID" project "$WORK/project"

CAPTURE=$(backend_capture "$ID")
assert_eq "$CAPTURE" $'line one\nline two' "backend_capture joins the terminal's tail lines"

: > "$ORCA_MOCK_LOG"
ORCA_MOCK_BUSY=0 backend_busy "$ID"
assert_eq "$?" "1" "backend_busy reports idle (exit 1) when 'terminal wait --for tui-idle' succeeds"

: > "$ORCA_MOCK_LOG"
ORCA_MOCK_BUSY=1 backend_busy "$ID"
assert_eq "$?" "0" "backend_busy reports busy (exit 0) when 'terminal wait --for tui-idle' times out"

: > "$ORCA_MOCK_LOG"
backend_send "$ID" Enter
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal send --terminal term_mock-1 --enter" \
  "backend_send maps 'Enter' to --enter with no text"

: > "$ORCA_MOCK_LOG"
backend_send "$ID" Escape
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal send --terminal term_mock-1 --text" \
  "backend_send maps 'Escape' to a raw --text payload"

: > "$ORCA_MOCK_LOG"
backend_send "$ID" C-c
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal send --terminal term_mock-1 --interrupt" \
  "backend_send maps 'C-c' to --interrupt"

: > "$ORCA_MOCK_LOG"
backend_send "$ID" "hello there"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal send --terminal term_mock-1 --text hello there --enter" \
  "backend_send maps plain text to --text ... --enter"

: > "$ORCA_MOCK_LOG"
backend_kill "$ID"
assert_eq "$?" "0" "backend_kill exits cleanly"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal close --worktree path:$WORKTREE --all" \
  "backend_kill closes every terminal in the task's worktree"
assert_file_exists "$WORKTREE/.git" "backend_kill does not touch the worktree"

: > "$ORCA_MOCK_LOG"
chief_meta_set "t-orca-nowt" endpoint "orca:term_mock-9"
backend_kill "t-orca-nowt"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal close --terminal term_mock-9 --tab" \
  "backend_kill falls back to closing the terminal's tab with no recorded worktree"

: > "$ORCA_MOCK_LOG"
backend_kill "t-orca-none"
assert_eq "$(cat "$ORCA_MOCK_LOG")" "" "backend_kill is a no-op for a task with no endpoint"

: > "$ORCA_MOCK_LOG"
BRIEF2="$WORK/brief2.md"
printf 'Reply with exactly the single word: ok\n' > "$BRIEF2"
backend_relaunch "$ID" "$BRIEF2"
RELAUNCH_RC=$?
assert_eq "$RELAUNCH_RC" "0" "backend_relaunch succeeds"

NEW_ENDPOINT=$(chief_meta_get "$ID" endpoint)
assert_eq "$NEW_ENDPOINT" "orca:term_mock-1" "backend_relaunch records a fresh orca:<handle> endpoint"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal create --worktree path:$WORKTREE --command claude --dangerously-skip-permissions --json" \
  "backend_relaunch creates a fresh terminal in the SAME (existing) worktree path"
assert_not_contains "$(cat "$ORCA_MOCK_LOG")" "worktree create" \
  "backend_relaunch never calls 'orca worktree create' (no new checkout)"

# --- parity with herdr: failure cleanup, rollback, teardown, full flow -----

# A failed brief delivery closes the terminal it just opened, and fails the spawn.
: > "$ORCA_MOCK_LOG"
ORCA_MOCK_SEND_FAIL=1 backend_spawn "t-orca-c" "$WORK/project" "$BRIEF" "chief/t-orca-c" 2>/dev/null
assert_eq "$?" "1" "backend_spawn fails when the brief can't be delivered"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal close --terminal term_mock-1 --tab" \
  "backend_spawn closes the terminal it opened when the brief can't be delivered"

# ...which leaves the worktree/branch for backend_spawn_cleanup to roll back,
# found by branch with no meta record. An unrelated worktree is left alone.
backend_spawn "t-orca-keep" "$WORK/project" "$BRIEF" "chief/t-orca-keep" >/dev/null 2>&1
assert_file_exists "$ORCA_MOCK_WORKTREES/t-orca-c/.git" "the failed spawn left its worktree behind"
: > "$ORCA_MOCK_LOG"
backend_spawn_cleanup "t-orca-c" "$WORK/project" "chief/t-orca-c"
assert_eq "$?" "0" "backend_spawn_cleanup exits cleanly"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "worktree rm --worktree path:$ORCA_MOCK_WORKTREES/t-orca-c --force" \
  "backend_spawn_cleanup has Orca remove the failed task's worktree"
assert_file_missing "$ORCA_MOCK_WORKTREES/t-orca-c" "backend_spawn_cleanup leaves no worktree on disk"
assert_eq "$(git -C "$WORK/project" branch --list 'chief/t-orca-c' | wc -l | tr -d ' ')" "0" \
  "backend_spawn_cleanup deletes the task's branch"
assert_file_exists "$ORCA_MOCK_WORKTREES/t-orca-keep/.git" "backend_spawn_cleanup leaves an unrelated worktree alone"

# A spawn that failed before the branch rename leaves Orca's own sanitized branch.
git -C "$WORK/project" worktree add -q -b t-orca-r "$ORCA_MOCK_WORKTREES/t-orca-r"
backend_spawn_cleanup "t-orca-r" "$WORK/project" "chief/t-orca-r"
assert_file_missing "$ORCA_MOCK_WORKTREES/t-orca-r" "backend_spawn_cleanup also finds a worktree still on Orca's own branch"
assert_eq "$(git -C "$WORK/project" branch --list 't-orca-r' | wc -l | tr -d ' ')" "0" \
  "backend_spawn_cleanup deletes Orca's own branch too"

: > "$ORCA_MOCK_LOG"
backend_spawn_cleanup "t-orca-never" "$WORK/project" "chief/t-orca-never"
assert_eq "$?" "0" "backend_spawn_cleanup is a no-op when nothing was created"
assert_not_contains "$(cat "$ORCA_MOCK_LOG")" "worktree rm" "backend_spawn_cleanup removes nothing when no worktree matches"

# backend_teardown makes Orca forget the worktree.
: > "$ORCA_MOCK_LOG"
backend_teardown "t-orca-keep" "$WORK/project" "$ORCA_MOCK_WORKTREES/t-orca-keep"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "worktree rm --worktree path:$ORCA_MOCK_WORKTREES/t-orca-keep --force" \
  "backend_teardown has Orca remove the worktree"

# The real lifecycle scripts end to end on this backend, same flow as herdr:
# spawn -> send -> interrupt -> relaunch -> teardown, ending with no worktree,
# branch or terminal left behind.
export CHIEF_BACKEND=orca
FLOW=t-orca-flow
: > "$ORCA_MOCK_LOG"
"$CHIEF_BIN/chief-spawn.sh" "$FLOW" "$WORK/project" --mode ship --branch feat/flow --intent "flow" >"$WORK/flow.out" 2>&1
assert_eq "$?" "0" "chief-spawn.sh succeeds on the orca backend"
FLOW_WT=$(chief_meta_get "$FLOW" worktree)
assert_eq "$FLOW_WT" "$ORCA_MOCK_WORKTREES/$FLOW" "chief-spawn.sh records the worktree path Orca chose"
assert_eq "$(chief_meta_get "$FLOW" endpoint)" "orca:term_mock-1" "chief-spawn.sh records the orca:<handle> endpoint"
assert_eq "$(chief_meta_get "$FLOW" status)" "working" "chief-spawn.sh marks the task working"
assert_eq "$(git -C "$FLOW_WT" rev-parse --abbrev-ref HEAD)" "feat/flow" "the task worktree is on the requested branch"

"$CHIEF_BIN/task/chief-send.sh" "$FLOW" "please continue" >/dev/null 2>&1
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal send --terminal term_mock-1 --text chief: instruction waiting in" \
  "chief-send.sh rings the doorbell in the task's terminal"

"$CHIEF_BIN/task/chief-control.sh" "$FLOW" interrupt >/dev/null 2>&1
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal send --terminal term_mock-1 --text $(printf '\033')" \
  "chief-control.sh interrupt sends Escape to the task's terminal"

: > "$ORCA_MOCK_LOG"
"$CHIEF_BIN/task/chief-control.sh" "$FLOW" relaunch --note "halfway" >/dev/null 2>&1
assert_eq "$?" "0" "chief-control.sh relaunch succeeds on the orca backend"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal close --worktree path:$FLOW_WT --all" "relaunch first closes the old terminals"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal create --worktree path:$FLOW_WT --command claude --dangerously-skip-permissions" \
  "relaunch starts a fresh bypass-permissions claude in the same worktree"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "halfway" "relaunch delivers the checkpoint note in the brief"

: > "$ORCA_MOCK_LOG"
"$CHIEF_BIN/chief-teardown.sh" "$FLOW" --abandon >/dev/null 2>&1
assert_eq "$?" "0" "chief-teardown.sh --abandon succeeds on the orca backend"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal close --worktree path:$FLOW_WT --all" "teardown closes the task's terminals"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "worktree rm --worktree path:$FLOW_WT --force" "teardown has Orca forget the worktree"
assert_file_missing "$FLOW_WT" "teardown removes the worktree"
assert_eq "$(git -C "$WORK/project" branch --list 'feat/flow' | wc -l | tr -d ' ')" "0" "teardown deletes the task's branch"

# A spawn whose brief can't be delivered rolls back through chief-spawn.sh.
FAIL=t-orca-flowfail
ORCA_MOCK_SEND_FAIL=1 "$CHIEF_BIN/chief-spawn.sh" "$FAIL" "$WORK/project" --mode ship --branch feat/flowfail --intent "x" >/dev/null 2>&1
assert_eq "$?" "1" "chief-spawn.sh fails when the orca backend can't deliver the brief"
assert_file_missing "$ORCA_MOCK_WORKTREES/$FAIL" "chief-spawn.sh's rollback leaves no Orca worktree behind"
assert_eq "$(git -C "$WORK/project" branch --list 'feat/flowfail' | wc -l | tr -d ' ')" "0" "chief-spawn.sh's rollback leaves no branch behind"
assert_file_missing "$CHIEF_HOME/state/$FAIL.meta" "chief-spawn.sh's rollback leaves no meta record"

harness_summary
