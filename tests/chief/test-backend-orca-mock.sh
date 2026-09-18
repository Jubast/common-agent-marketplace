#!/usr/bin/env bash
# test-backend-orca-mock.sh - zero-cost unit test of chief-backend-orca.sh's
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
  echo "  (skipped - jq not on PATH, required by chief-backend-orca.sh)"
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
. "$CHIEF_BIN/lib/chief-paths.sh"
. "$CHIEF_BIN/lib/chief-meta.sh"
. "$CHIEF_BIN/lib/chief-backend-orca.sh"

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
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal create --worktree path:$WORKTREE --command claude --json" \
  "backend_spawn calls 'orca terminal create' scoped to the worktree path Orca just made"
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
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal close --terminal term_mock-1 --tab" \
  "backend_kill closes the terminal's whole tab"
assert_file_exists "$WORKTREE/.git" "backend_kill does not touch the worktree"

: > "$ORCA_MOCK_LOG"
BRIEF2="$WORK/brief2.md"
printf 'Reply with exactly the single word: ok\n' > "$BRIEF2"
backend_relaunch "$ID" "$BRIEF2"
RELAUNCH_RC=$?
assert_eq "$RELAUNCH_RC" "0" "backend_relaunch succeeds"

NEW_ENDPOINT=$(chief_meta_get "$ID" endpoint)
assert_eq "$NEW_ENDPOINT" "orca:term_mock-1" "backend_relaunch records a fresh orca:<handle> endpoint"
assert_contains "$(cat "$ORCA_MOCK_LOG")" "terminal create --worktree path:$WORKTREE --command claude --json" \
  "backend_relaunch creates a fresh terminal in the SAME (existing) worktree path"
assert_not_contains "$(cat "$ORCA_MOCK_LOG")" "worktree create" \
  "backend_relaunch never calls 'orca worktree create' (no new checkout)"

harness_summary
