#!/usr/bin/env bash
# test-backend-herdr.sh - exercises herdr.sh's five adapter
# functions against a REAL herdr install and a real (minimal) claude turn.
#
# Unlike every other file in this directory, this one is NOT zero-cost: it
# needs `herdr` on PATH, a headless herdr server, and spends a small number
# of real tokens on one trivial claude prompt ("reply with exactly: ok").
# Opt in explicitly:
#
#   CHIEF_TEST_HERDR=1 bash tests/chief/test-backend-herdr.sh
#
# Skips cleanly (exit 0) if herdr isn't installed or the opt-in isn't set,
# so it's safe for run-tests.sh's default sweep and outside the devcontainer.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-backend-herdr:"

if [ "${CHIEF_TEST_HERDR:-0}" != "1" ]; then
  echo "  (skipped - opt in with CHIEF_TEST_HERDR=1; spends real tokens and needs herdr)"
  exit 0
fi

if ! command -v herdr >/dev/null 2>&1; then
  echo "  (skipped - herdr not on PATH)"
  exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "  (skipped - claude CLI not on PATH)"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "  (skipped - jq not on PATH, required by backends/herdr.sh)"
  exit 0
fi

# herdr's server is a per-machine singleton (one socket under
# ~/.config/herdr/) - reuse one that's already running, only start (and
# later stop) our own if none is.
STARTED_SERVER=0
if ! herdr status --json 2>/dev/null | grep -q '"running":true'; then
  nohup herdr server >/tmp/chief-test-herdr-server.log 2>&1 < /dev/null &
  disown
  STARTED_SERVER=1
  for _ in $(seq 1 20); do
    herdr status --json 2>/dev/null | grep -q '"running":true' && break
    sleep 0.5
  done
fi
herdr status --json 2>/dev/null | grep -q '"running":true' \
  || { echo "  [FAIL] could not start a herdr server"; harness_summary; exit 1; }

WORK=$(mktemp -d)
ID=t-herdr-1
cleanup() {
  # Safety net independent of how far the test got: close every workspace
  # this run could have produced, even if backend_spawn/relaunch failed
  # partway through and left one open without ever reporting it. Covers
  # both our own "chief-<id>"-labeled linked-worktree workspaces AND the
  # separate auto-created "primary" workspace `herdr worktree create` opens
  # for the scratch project checkout itself (repo_root match).
  herdr workspace list 2>/dev/null \
    | jq -r --arg label "chief-$ID" --arg root "$WORK/project" \
        '.result.workspaces[]? | select(.label == $label or .worktree.repo_root == $root) | .workspace_id' 2>/dev/null \
    | while read -r ws; do herdr workspace close "$ws" >/dev/null 2>&1 || true; done
  [ "$STARTED_SERVER" = 1 ] && herdr server stop >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/project" && cd "$WORK/project"
git init -q -b main
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

export CHIEF_HOME="$WORK/.chief"
. "$CHIEF_BIN/lib/paths.sh"
. "$CHIEF_BIN/lib/meta.sh"
. "$CHIEF_BIN/lib/backends/herdr.sh"

BRIEF="$WORK/brief.md"
printf 'Reply with exactly the single word: ok\n' > "$BRIEF"

# Structural (non-racy) proof that a brand-new worktree path really does
# trigger Claude Code's trust dialog on `agent start`, before trusting
# backend_spawn to have exercised _chief_herdr_start_agent's handling of it
# below. A throwaway probe pane, closed immediately - no claude turn, no
# tokens spent.
PROBE_ID="$ID-probe"
PROBE_JSON=$(herdr worktree create --cwd "$WORK/project" --branch "chief/$PROBE_ID" \
  --path "$WORK/.chief/worktrees/$PROBE_ID" --label "chief-$PROBE_ID" --trust-repository --no-focus 2>/dev/null)
PROBE_PANE=$(printf '%s' "$PROBE_JSON" | jq -r '.result.root_pane.pane_id // empty')
herdr agent start "$PROBE_ID" --kind claude --pane "$PROBE_PANE" --timeout 30000 >/dev/null 2>"$WORK/probe.err"
assert_contains "$(cat "$WORK/probe.err")" "agent_not_ready" \
  "a brand-new worktree path hits Claude Code's trust dialog on 'agent start' (not just an immediately-idle agent)"
herdr workspace close "$(_chief_herdr_workspace_id "$PROBE_PANE")" >/dev/null 2>&1
git -C "$WORK/project" worktree remove --force "$WORK/.chief/worktrees/$PROBE_ID" >/dev/null 2>&1 || true
git -C "$WORK/project" branch -D "chief/$PROBE_ID" >/dev/null 2>&1 || true

SPAWN_OUTPUT=$(backend_spawn "$ID" "$WORK/project" "$BRIEF" "chief/$ID" 2>"$WORK/spawn.err")
SPAWN_RC=$?
assert_eq "$SPAWN_RC" "0" "backend_spawn succeeds (clears the same trust dialog internally, then delivers the brief)"
[ "$SPAWN_RC" = "0" ] || cat "$WORK/spawn.err"

WORKTREE=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 1p)
ENDPOINT=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 2p)

assert_eq "$WORKTREE" "$WORK/.chief/worktrees/$ID" "backend_spawn prints the worktree path first"
assert_contains "$ENDPOINT" "herdr:" "backend_spawn prints a herdr: endpoint second"
assert_file_exists "$WORKTREE/.git" "backend_spawn actually created the git worktree"

chief_meta_set "$ID" endpoint "$ENDPOINT"
chief_meta_set "$ID" worktree "$WORKTREE"
chief_meta_set "$ID" project "$WORK/project"

# backend_capture's >viewport read only works once the agent is off
# "working" - _chief_herdr_prompt's own --wait only waits for the turn to
# START, not finish.
herdr agent wait "$ID" --until idle --until done --timeout 30000 >/dev/null 2>&1
CAPTURE=$(backend_capture "$ID")
assert_contains "$CAPTURE" "ok" "backend_capture shows the claude reply"

backend_busy "$ID"
assert_eq "$?" "1" "backend_busy reports idle (not busy) once the reply is done"

# _chief_herdr_prompt_box_has_text against REAL herdr rendering: Claude Code
# fills a never-yet-prompted box with a dim placeholder hint until the first
# real turn, which a bare-emptiness check misreads as pending text (caught
# in manual verification, not hypothetical) - confirm the needle-match
# check doesn't do that, and does catch our own text genuinely in flight.
assert_failure "_chief_herdr_prompt_box_has_text misses text that was never sent" -- \
  _chief_herdr_prompt_box_has_text "$ID" "never sent to this pane xyz123"

BRIEF3="$WORK/brief3.md"
printf 'Reply with exactly the single word: done\n' > "$BRIEF3"
( herdr agent prompt "$ID" "$(cat "$BRIEF3")" --wait --until working --until blocked --timeout 30000 \
    >"$WORK/prompt3.json" 2>&1 ) &
PROMPT_PID=$!
CAUGHT=0
for _ in $(seq 1 60); do
  _chief_herdr_prompt_box_has_text "$ID" "$(cat "$BRIEF3")" && { CAUGHT=1; break; }
  sleep 0.05
done
wait "$PROMPT_PID"
assert_eq "$CAUGHT" "1" "_chief_herdr_prompt_box_has_text catches our own text while genuinely in flight"

herdr agent wait "$ID" --until idle --until done --timeout 30000 >/dev/null 2>&1
CAPTURE2=$(backend_capture "$ID")
assert_contains "$CAPTURE2" "done" "the raced-in prompt still completed normally"

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
assert_contains "$NEW_ENDPOINT" "herdr:" "backend_relaunch records a fresh herdr endpoint"
[ "$NEW_ENDPOINT" != "$ENDPOINT" ]
assert_eq "$?" "0" "backend_relaunch's endpoint differs from the original pane"

herdr agent wait "$ID" --until idle --until done --timeout 30000 >/dev/null 2>&1
RELAUNCH_CAPTURE=$(backend_capture "$ID")
assert_contains "$RELAUNCH_CAPTURE" "ok" "backend_capture shows the relaunched claude's reply"

backend_kill "$ID"

harness_summary
