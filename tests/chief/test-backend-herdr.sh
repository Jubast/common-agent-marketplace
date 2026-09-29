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

# backend_spawn/backend_relaunch only wait for the first turn to START, not
# finish (see herdr.sh's own header) - poll backend_busy before asserting
# on the reply so a trivial task's own completion time isn't a race.
wait_for_idle() {  # <id> [timeout-s]
  local id=$1 timeout=${2:-30} waited=0
  while [ "$waited" -lt "$timeout" ]; do
    backend_busy "$id" || return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}
_ws_count_for_root() {  # <repo-root> -> number of herdr workspaces open for it
  herdr workspace list 2>/dev/null \
    | jq -r --arg root "$1" '[.result.workspaces[]? | select(.worktree.repo_root == $root)] | length'
}
_tab_id_with_label() {  # <workspace-id> <label> -> its tab_id, or empty
  herdr tab list --workspace "$1" 2>/dev/null \
    | jq -r --arg label "$2" '.result.tabs[]? | select(.label == $label) | .tab_id'
}
_ws_exists() {  # <workspace-id> -> the id again if still open, else empty
  herdr workspace list 2>/dev/null \
    | jq -r --arg id "$1" '.result.workspaces[]? | select(.workspace_id == $id) | .workspace_id'
}
cleanup() {
  # Safety net independent of how far the test got: close every workspace
  # this run could have produced, even if backend_spawn/relaunch failed
  # partway through and left one open without ever reporting it. Covers
  # both our own "chief-<id>"-labeled linked-worktree workspaces AND the
  # separate auto-created "primary" workspace `herdr worktree create` opens
  # for the scratch project checkout itself (repo_root match).
  herdr workspace list 2>/dev/null \
    | jq -r --arg label "chief-$ID" --arg work "$WORK" \
        '.result.workspaces[]? | select((.label | startswith($label)) or (.worktree.repo_root // "" | startswith($work))) | .workspace_id' 2>/dev/null \
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
# The probe above may itself have auto-opened a "primary" workspace for
# $WORK/project as a side effect (herdr's own behavior on a repo root with
# none open yet) - close it too, so backend_spawn below is what creates the
# shared project workspace, not a reuse of this leftover.
PROBE_PRIMARY=$(_chief_herdr_primary_workspace_id "$WORK/project")
[ -n "$PROBE_PRIMARY" ] && herdr workspace close "$PROBE_PRIMARY" >/dev/null 2>&1

SPAWN_OUTPUT=$(backend_spawn "$ID" "$WORK/project" "$BRIEF" "chief/$ID" 2>"$WORK/spawn.err")
SPAWN_RC=$?
assert_eq "$SPAWN_RC" "0" "backend_spawn succeeds (clears the same trust dialog internally, then delivers the brief)"
[ "$SPAWN_RC" = "0" ] || cat "$WORK/spawn.err"

WORKTREE=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 1p)
ENDPOINT=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 2p)

assert_eq "$WORKTREE" "$WORK/.chief/worktrees/$ID" "backend_spawn prints the worktree path first"
assert_contains "$ENDPOINT" "herdr:" "backend_spawn prints a herdr: endpoint second"
assert_file_exists "$WORKTREE/.git" "backend_spawn actually created the git worktree"

# Nesting: the task's pane must live inside the project's shared primary
# workspace, as a labeled tab, not in its own standalone workspace.
PRIMARY=$(_chief_herdr_primary_workspace_id "$WORK/project")
assert_eq "$(_chief_herdr_workspace_id "${ENDPOINT#herdr:}")" "$PRIMARY" "backend_spawn nests the task's pane inside the project's shared primary workspace"
[ -n "$(_tab_id_with_label "$PRIMARY" "chief-$ID")" ]
assert_eq "$?" "0" "the nested tab keeps the chief-<id> label"
assert_eq "$(_ws_count_for_root "$WORK/project")" "1" "only one herdr workspace exists for the project - no standalone task workspace"

chief_meta_set "$ID" endpoint "$ENDPOINT"
chief_meta_set "$ID" worktree "$WORKTREE"
chief_meta_set "$ID" project "$WORK/project"

# A second task against the SAME project must reuse that one shared
# workspace too, not create a second one.
ID2="$ID-2"
BRIEF4="$WORK/brief4.md"
printf 'Reply with exactly the single word: ok\n' > "$BRIEF4"
SPAWN_OUTPUT2=$(backend_spawn "$ID2" "$WORK/project" "$BRIEF4" "chief/$ID2" 2>"$WORK/spawn2.err")
SPAWN_RC2=$?
assert_eq "$SPAWN_RC2" "0" "backend_spawn succeeds for a second task against the same project"
[ "$SPAWN_RC2" = "0" ] || cat "$WORK/spawn2.err"
ENDPOINT2=$(printf '%s\n' "$SPAWN_OUTPUT2" | sed -n 2p)
WORKTREE2=$(printf '%s\n' "$SPAWN_OUTPUT2" | sed -n 1p)
assert_eq "$(_chief_herdr_workspace_id "${ENDPOINT2#herdr:}")" "$PRIMARY" "a second task nests into the SAME shared project workspace, not a new one"
assert_eq "$(_ws_count_for_root "$WORK/project")" "1" "still only one herdr workspace for the project after a second task"

chief_meta_set "$ID2" endpoint "$ENDPOINT2"
chief_meta_set "$ID2" worktree "$WORKTREE2"
chief_meta_set "$ID2" project "$WORK/project"
backend_kill "$ID2"
assert_eq "$(_tab_id_with_label "$PRIMARY" "chief-$ID2")" "" "backend_kill closes only the second task's own tab"
assert_eq "$(_chief_herdr_primary_workspace_id "$WORK/project")" "$PRIMARY" "the shared project workspace survives backend_kill of one of its tasks"
git -C "$WORK/project" worktree remove --force "$WORKTREE2" >/dev/null 2>&1 || true
git -C "$WORK/project" branch -D "chief/$ID2" >/dev/null 2>&1 || true

wait_for_idle "$ID"
CAPTURE=$(backend_capture "$ID")
assert_contains "$CAPTURE" "ok" "backend_capture shows the claude reply"
assert_contains "$CAPTURE" "bypass permissions" "backend_spawn starts the worker with bypass permissions on"

backend_busy "$ID"
assert_eq "$?" "1" "backend_busy reports idle (not busy) once the reply is done"

# _chief_herdr_prompt_box_has_text against REAL herdr rendering: Claude Code
# fills a never-yet-prompted box with a dim placeholder hint until the first
# real turn, which a bare-emptiness check would misread as pending text -
# confirm the needle-match check doesn't, and does catch our own text
# genuinely in flight.
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

wait_for_idle "$ID"
CAPTURE2=$(backend_capture "$ID")
assert_contains "$CAPTURE2" "done" "the raced-in prompt still completed normally"

assert_success "backend_send delivers a special key without erroring" -- backend_send "$ID" Escape

backend_kill "$ID"
assert_eq "$?" "0" "backend_kill exits cleanly"
assert_file_exists "$WORKTREE/.git" "backend_kill does not touch the worktree"
assert_eq "$(_chief_herdr_primary_workspace_id "$WORK/project")" "$PRIMARY" "backend_kill leaves the shared project workspace open - only the task's own tab closes"

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
assert_eq "$(_chief_herdr_workspace_id "${NEW_ENDPOINT#herdr:}")" "$PRIMARY" "backend_relaunch re-nests the task into the same shared project workspace"

wait_for_idle "$ID"
RELAUNCH_CAPTURE=$(backend_capture "$ID")
assert_contains "$RELAUNCH_CAPTURE" "ok" "backend_capture shows the relaunched claude's reply"

backend_kill "$ID"
assert_eq "$(_chief_herdr_primary_workspace_id "$WORK/project")" "$PRIMARY" "the shared project workspace stays open with just its own tab after all its tasks are killed"

# _chief_herdr_close_pane_by_label's orphan-pane cleanup: `herdr worktree
# create`/`open` silently opens a "primary" workspace for the project
# itself (labeled after the project, not chief-<id>) alongside the
# intended one whenever the project doesn't already have one open. On a
# failed spawn that's a second orphan - exercised directly against real
# herdr state, without needing to force an actual agent-start/prompt
# failure.
CLEANUP_PROJECT="$WORK/cleanup-project"
mkdir -p "$CLEANUP_PROJECT" && cd "$CLEANUP_PROJECT"
git init -q -b main
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cd "$WORK"

CLEANUP_ID=t-herdr-cleanup
herdr worktree create --cwd "$CLEANUP_PROJECT" --branch "chief/$CLEANUP_ID" \
  --path "$WORK/.chief/worktrees/$CLEANUP_ID" --label "chief-$CLEANUP_ID" \
  --trust-repository --no-focus >/dev/null 2>&1
_chief_herdr_close_pane_by_label "$CLEANUP_ID" "$CLEANUP_PROJECT" ""
assert_eq "$(_ws_count_for_root "$CLEANUP_PROJECT")" "0" "cleanup closes both the chief-<id> pane and the freshly-orphaned primary workspace"

# The OTHER case: the label has already moved onto a TAB inside a shared
# project workspace (a failure between _chief_herdr_nest_into_primary
# succeeding and agent start/prompt) - a workspace-label lookup alone
# would find nothing here.
NEST_ID=t-herdr-nested-cleanup
NEST_PRIMARY_JSON=$(herdr worktree open --cwd "$CLEANUP_PROJECT" --path "$CLEANUP_PROJECT" --trust-repository --no-focus 2>&1)
NEST_PRIMARY=$(printf '%s' "$NEST_PRIMARY_JSON" | jq -r '.result.workspace.workspace_id')
NEST_JSON=$(herdr worktree create --cwd "$CLEANUP_PROJECT" --branch "chief/$NEST_ID" \
  --path "$WORK/.chief/worktrees/$NEST_ID" --label "chief-$NEST_ID" --trust-repository --no-focus 2>&1)
NEST_PANE=$(printf '%s' "$NEST_JSON" | jq -r '.result.root_pane.pane_id')
_chief_herdr_nest_into_primary "$NEST_PRIMARY" "$NEST_PANE" "$NEST_ID" >/dev/null
_chief_herdr_close_pane_by_label "$NEST_ID" "$CLEANUP_PROJECT" "$NEST_PRIMARY"
assert_eq "$(_tab_id_with_label "$NEST_PRIMARY" "chief-$NEST_ID")" "" "cleanup closes an already-nested task's tab too, not just a standalone workspace"
assert_eq "$(_ws_exists "$NEST_PRIMARY")" "$NEST_PRIMARY" "cleanup never closes the shared project workspace itself when only the task's own tab needed removing"
herdr workspace close "$NEST_PRIMARY" >/dev/null 2>&1 || true

# A primary workspace that predates the failed spawn (an operator already
# working in the project) must survive cleanup untouched.
OP_JSON=$(herdr worktree open --cwd "$CLEANUP_PROJECT" --path "$CLEANUP_PROJECT" --trust-repository --no-focus 2>&1)
OP_WS=$(printf '%s' "$OP_JSON" | jq -r '.result.workspace.workspace_id')
PRE_PRIMARY=$(_chief_herdr_primary_workspace_id "$CLEANUP_PROJECT")
assert_eq "$PRE_PRIMARY" "$OP_WS" "_chief_herdr_primary_workspace_id finds the pre-existing primary workspace"

herdr worktree create --cwd "$CLEANUP_PROJECT" --branch "chief/${CLEANUP_ID}-2" \
  --path "$WORK/.chief/worktrees/${CLEANUP_ID}-2" --label "chief-${CLEANUP_ID}-2" \
  --trust-repository --no-focus >/dev/null 2>&1
_chief_herdr_close_pane_by_label "${CLEANUP_ID}-2" "$CLEANUP_PROJECT" "$PRE_PRIMARY"
assert_eq "$(_ws_exists "$OP_WS")" "$OP_WS" "cleanup never touches a primary workspace that predates the failed spawn"
herdr workspace close "$OP_WS" >/dev/null 2>&1 || true

harness_summary
