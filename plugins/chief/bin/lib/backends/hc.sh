#!/usr/bin/env bash
# hc.sh - herdr-core (`hc`) backend adapter, verified against hc 0.1.20
# (`hc --skill` is its own usage guide; re-check it after an upgrade).
#
# hc has no worktrees or workspaces: the adapter makes the worktree with git and
# starts one terminal per task, running the agent's own command. The terminal's
# name and its `chief.task` label are the task id. Every call finds the terminal
# by that label, never by the endpoint ("hc:<address>", display only): addresses
# restart at t1 when hc's state is wiped. The labels herdr.space/herdr.tab make
# the Herdr app show the terminal as a space of its own.
#
# The brief's CONTENT is the first prompt (`hc send`, one bracketed paste). hc
# answers `started`: true once the agent reports its turn, null if it reports no
# status; then the screen settles it (screen.sh). Readiness is read off the
# screen as well: some agents report `idle` while their trust dialog shows.
#
# The terminal runs without --keep (a lost agent would come back as a shell under
# the task's labels) and with --no-parent (a child of Chief's own terminal would
# end with it). A live terminal with a `reason` (the first look after the loss) or
# an argv that is not the agent's is such a recovered shell, not the agent.
# Chief never stops the core: any `hc` call starts one, and `hc server stop`
# would end the operator's terminals.
#
# CHIEF_HC_START_WAIT (s) bounds the wait for the agent's ready screen,
# CHIEF_HC_PROMPT_WAIT (s) the screen recovery of the first prompt.
CHIEF_HC_START_WAIT="${CHIEF_HC_START_WAIT:-60}"
CHIEF_HC_PROMPT_WAIT="${CHIEF_HC_PROMPT_WAIT:-20}"

# shellcheck source=/dev/null
. "$CHIEF_ROOT/bin/lib/backends/screen.sh"

# The hooks screen.sh drives.
_chief_screen_read() { hc read "$1" 2>/dev/null; }
_chief_screen_send() { hc send "$1" --json -- "$2" >/dev/null 2>&1; }
_chief_screen_keys() { hc keys "$@"; }

# _chief_hc_agent <id> - `hc get` of the task's live agent terminal, as JSON.
_chief_hc_agent() {
  local address json exe
  chief_agent_use "$1" || return 1
  exe=$(chief_agent_command); exe=${exe%% *}
  for address in $(hc ls --label "chief.task=$1" --json 2>/dev/null | jq -r '.terminals[] | select(.state == "live") | .address'); do
    json=$(hc get "$address" --json 2>/dev/null) || continue
    printf '%s' "$json" | jq -e --arg exe "$exe" '.reason == null and .argv[0] == $exe' >/dev/null || continue
    printf '%s\n' "$json"
    return 0
  done
  return 1
}

_chief_hc_address() { _chief_hc_agent "$1" | jq -er .address; }

# _chief_hc_discard <id> - kills and removes every terminal of the task, finished
# ones too: a finished terminal keeps the task's name.
_chief_hc_discard() {
  local address
  for address in $(hc ls --all --label "chief.task=$1" --json 2>/dev/null | jq -r '.terminals[].address'); do
    hc kill "$address" >/dev/null 2>&1
    hc rm "$address" >/dev/null 2>&1
  done
  return 0
}

# _chief_hc_prompt <address> <text> - submit <text>; 0 once the turn is observed
# started. A reply other than `started: true` is settled from the screen, except
# a blocked agent: a permission prompt nobody is present to answer.
_chief_hc_prompt() {
  local address=$1 text=$2 reply rc=0
  reply=$(hc send "$address" --json -- "$text" 2>&1) || rc=$?
  case $rc in
    0) ;;
    9) echo "chief-backend-hc: $address is blocked at an unanswered permission prompt - no one is present to answer it" >&2; return 1 ;;
    *) echo "chief-backend-hc: 'hc send' failed for $address (exit $rc): $reply" >&2; return 1 ;;
  esac
  printf '%s' "$reply" | jq -e '.started == true' >/dev/null && return 0
  _chief_screen_settle "$address" "$text" "$CHIEF_HC_PROMPT_WAIT"
}

# _chief_hc_launch <id> <worktree> <brief-path> -> starts the agent in the
# worktree, submits the brief, prints the terminal's address. Removes the new
# terminal if that fails.
_chief_hc_launch() {
  local id=$1 worktree=$2 brief_path=$3 json address
  json=$(hc run --bg --json --no-parent --name "$id" --cwd "$worktree" \
           --label "chief.task=$id" --label "herdr.space=chief-$id" --label "herdr.tab=chief-$id" \
           -- $(chief_agent_command) 2>&1) \
    || { echo "chief-backend-hc: 'hc run' failed: $json" >&2; return 1; }
  address=$(printf '%s' "$json" | jq -r '.address // empty')
  [ -n "$address" ] || { echo "chief-backend-hc: could not read the address from: $json" >&2; return 1; }

  { _chief_screen_start_ready "$address" "$CHIEF_HC_START_WAIT" "$worktree" \
      && _chief_hc_prompt "$address" "$(cat "$brief_path")"; } \
    || { _chief_hc_discard "$id"; return 1; }

  printf '%s\n' "$address"
}

backend_spawn() {
  local id=$1 project_dir=$2 brief_path=$3 branch=$4
  local worktree="$WORKTREES/$id" address
  chief_agent_use "$id" || return 1
  git -C "$project_dir" worktree add -q -b "$branch" "$worktree" \
    || { echo "chief-backend-hc: 'git worktree add' failed for $worktree on $branch" >&2; return 1; }
  agent_prepare "$worktree"
  address=$(_chief_hc_launch "$id" "$worktree" "$brief_path") \
    || { backend_spawn_cleanup "$id" "$project_dir" "$branch"; return 1; }

  printf '%s\n' "$worktree"
  printf 'hc:%s\n' "$address"
}

# backend_spawn_cleanup <id> <project-dir> <branch> - best-effort rollback
# after backend_spawn itself failed, or chief-spawn.sh couldn't parse its
# output. See backend.sh's contract header for the calling convention.
backend_spawn_cleanup() {
  local id=$1 project_dir=$2 branch=$3
  local worktree="$WORKTREES/$id"
  _chief_hc_discard "$id"
  chief_agent_release "$id" "$worktree"
  git -C "$project_dir" worktree remove --force "$worktree" >/dev/null 2>&1 || rm -rf "$worktree"
  git -C "$project_dir" branch -D "$branch" >/dev/null 2>&1 || true
}

backend_send() {
  local id=$1 text=$2 address
  address=$(_chief_hc_address "$id") || return 1
  case "$text" in
    Enter)  hc keys "$address" enter ;;
    Escape) hc keys "$address" esc ;;
    C-c)    hc keys "$address" ctrl+c ;;
    *)      hc send "$address" -- "$text" ;;
  esac >/dev/null
}

backend_attach_hint() {
  printf 'hc attach %s (ctrl+\\ detaches)\n' "$1"
}

backend_busy() {
  _chief_hc_agent "$1" | jq -e '.status.state == "working"' >/dev/null || return 1
}

backend_kill() {
  _chief_hc_discard "$1"
}

backend_teardown() {
  chief_agent_release "$1" "$3"
}

backend_relaunch() {
  local id=$1 brief_path=$2 worktree address
  worktree=$(chief_meta_get "$id" worktree)
  chief_agent_use "$id" || return 1
  agent_prepare "$worktree"
  address=$(_chief_hc_launch "$id" "$worktree" "$brief_path") || return 1
  chief_meta_set "$id" endpoint "hc:$address"
}
