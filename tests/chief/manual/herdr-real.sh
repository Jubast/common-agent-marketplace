#!/usr/bin/env bash
# herdr-real.sh - MANUAL. Runs herdr.sh against a REAL claude: the
# three things real Claude Code rendering does that the stand-in agent of
# ../backends/herdr.bats can only imitate - the folder-trust dialog, the dim
# placeholder hint in a never-prompted input box, and our own text in the input
# line while a prompt is in flight. Everything else is covered there for free.
#
# NOT zero-cost: three trivial claude turns ("reply with exactly: ok").
# Opt in explicitly:
#
#   CHIEF_TEST_HERDR=1 bash tests/chief/manual/herdr-real.sh
#
# Skips cleanly (exit 0) without the opt-in, herdr, claude, jq, ss or a claude
# login (ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN, or .credentials.json in
# the claude config dir). Never touches the caller's herdr or ~/.claude.json: it
# runs in the scrubbed environment of lib/isolation.sh (own HOME/XDG dirs, own
# herdr server and socket, own CLAUDE_CONFIG_DIR) and aborts unless that
# isolation is proven. Only the claude login is copied in, and removed on exit.
#
# CHIEF_TEST_HERDR_GUARD_ONLY=1 runs the isolation guard alone, spending nothing.
# run-tests.sh never runs it.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "herdr-real:"

if [ "${CHIEF_TEST_HERDR:-0}" != "1" ]; then
  echo "  (skipped - opt in with CHIEF_TEST_HERDR=1; spends real tokens and needs herdr)"
  exit 0
fi
ISO_CLIS="herdr jq ss"
[ "${CHIEF_TEST_HERDR_GUARD_ONLY:-0}" = 1 ] || ISO_CLIS+=" claude"
. "$TEST_DIR/lib/isolation.sh"

# The login: an env token passes through the scrub; otherwise copy the file.
if [ -z "${ANTHROPIC_API_KEY:-}${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  [ -f "$REAL_CLAUDE_DIR/.credentials.json" ] \
    || { echo "  (skipped - no claude login: set ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN, or log in)"; exit 0; }
  ( umask 077; cp "$REAL_CLAUDE_DIR/.credentials.json" "$CLAUDE_CONFIG_DIR/.credentials.json" ) \
    || { echo "  [FAIL] could not copy the claude login"; exit 1; }
fi
# Seed to skip claude's first-run screens; never run against a real claude.
echo '{"hasCompletedOnboarding":true}' > "$CLAUDE_CONFIG_DIR/.claude.json"

WORK="$ISO/work"
mkdir -p "$WORK/project" && cd "$WORK/project"
git init -q -b main
git commit -q --allow-empty -m init

export CHIEF_HOME="$WORK/.chief"
. "$CHIEF_BIN/lib/paths.sh"
chief_ensure_dirs
. "$CHIEF_BIN/lib/meta.sh"
. "$CHIEF_BIN/lib/agents/agent.sh"
. "$CHIEF_BIN/lib/backends/herdr.sh"

capture() { herdr agent read "$1" --source recent-unwrapped --lines 200 2>/dev/null; }
# backend_spawn only waits for the first turn to START: poll backend_busy
# before asserting on the reply.
wait_for_idle() {  # <id> [timeout-s]
  local id=$1 timeout=${2:-30} waited=0
  while [ "$waited" -lt "$timeout" ]; do
    backend_busy "$id" || return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}
# spawn_task <id> - backend_spawn as chief-spawn.sh calls it, one trivial brief
spawn_task() {
  local id=$1 out
  printf 'Reply with exactly the single word: ok\n' > "$WORK/brief-$id.md"
  chief_meta_set "$id" mode builder
  chief_meta_set "$id" project "$WORK/project"
  chief_meta_set "$id" agent claude
  out=$(backend_spawn "$id" "$WORK/project" "$WORK/brief-$id.md" "chief/$id" 2>"$WORK/spawn-$id.err")
  SPAWN_RC=$?
  [ "$SPAWN_RC" = 0 ] || cat "$WORK/spawn-$id.err"
  chief_meta_set "$id" worktree "$(sed -n 1p <<< "$out")"
  chief_meta_set "$id" endpoint "$(sed -n 2p <<< "$out")"
}

# --- a pre-trusted worktree: no dialog, the reply and the unattended flag show ---
spawn_task t-real-1
assert_eq "$SPAWN_RC" 0 "backend_spawn starts real claude in a pre-trusted worktree"
wait_for_idle t-real-1
CAPTURE=$(capture t-real-1)
assert_contains "$CAPTURE" "ok" "the pane shows the claude reply"
assert_contains "$CAPTURE" "bypass permissions" "claude runs with bypass permissions on"

# --- the folder-trust dialog: a worktree nobody pre-trusted ---
CHIEF_NO_PRETRUST=1 spawn_task t-real-2
assert_eq "$SPAWN_RC" 0 "backend_spawn accepts real claude's folder-trust dialog"
wait_for_idle t-real-2
assert_contains "$(capture t-real-2)" "ok" "claude answers after the dialog"

# --- the input-line check against real rendering ---
# Claude Code fills a never-yet-prompted box with a dim placeholder hint, which a
# bare-emptiness check would misread as pending text; the needle match must not,
# and must catch our own text in flight.
chief_agent_use t-real-1
box_has() {  # <id> <text>
  herdr agent read "$1" --source detection --lines 40 2>/dev/null | chief_agent_input_line \
    | chief_agent_has_text "$(printf '%s' "$2" | tr -s '[:space:]' ' ' | cut -c1-24)"
}
assert_failure "the input-line check misses text that was never sent" -- box_has t-real-2 "never sent to this pane xyz123"

PROMPT="Reply with exactly the single word: done"
( herdr agent prompt t-real-1 "$PROMPT" --wait --until working --until blocked --timeout 30000 \
    >"$WORK/prompt.json" 2>&1 ) &
PROMPT_PID=$!
CAUGHT=0
for _ in $(seq 1 60); do
  box_has t-real-1 "$PROMPT" && { CAUGHT=1; break; }
  sleep 0.05
done
wait "$PROMPT_PID"
assert_eq "$CAUGHT" 1 "the input-line check catches our own text while it is in flight"
wait_for_idle t-real-1
assert_contains "$(capture t-real-1)" "done" "the raced-in prompt still completed normally"

backend_kill t-real-1
backend_kill t-real-2
harness_summary
