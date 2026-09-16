#!/usr/bin/env bash
# chief-backend-orca.sh - Orca backend adapter, matched against a live Orca
# CLI (`orca --help` / `orca agent-context --json`, schema v1).
#
# `orca worktree create` can't pin an exact path/branch (only --name), so
# this adapter does `git worktree add` itself (like chief-backend-mock.sh)
# and attaches an Orca terminal to that path via `orca terminal create
# --worktree path:<path>` - Orca's own recommended way to launch an agent in
# an existing worktree. Endpoint format: "orca:<terminal-handle>".
#
# Sends the brief's CONTENT (not its path) as the first prompt: same reason
# as chief-backend-herdr.sh - the brief lives outside the worktree, so
# telling claude to Read it would hit the "outside working directory" dialog.
#
# busy/idle: `orca terminal wait --for tui-idle --timeout-ms <n>` returns ok
# once idle, or a timeout error while busy (confirmed live) - used below as
# a non-blocking poll.
#
# Unverified - confirm with CHIEF_TEST_ORCA=1 tests/chief/test-backend-orca.sh:
#   - whether --worktree path:<p> resolves a worktree Orca hasn't seen yet
#   - the down-arrow byte sequence _chief_orca_accept_trust_dialog sends

_chief_orca_warn_once() {
  [ -n "${_CHIEF_ORCA_WARNED:-}" ] && return
  _CHIEF_ORCA_WARNED=1
  echo "chief-backend-orca: unverified end-to-end - see this file's header" >&2
}

# _chief_orca_accept_trust_dialog <handle> - clears claude's first-run
# trust dialog if present (down, enter), then waits for idle.
_chief_orca_accept_trust_dialog() {
  local handle=$1
  local read_json tail
  read_json=$(orca terminal read --terminal "$handle" --limit 40 --json 2>/dev/null)
  tail=$(printf '%s' "$read_json" | jq -r '.result.terminal.tail // [] | join("\n")' 2>/dev/null)
  case "$tail" in
    *"trust this folder"*)
      orca terminal send --terminal "$handle" --text $'\x1b[B' >/dev/null 2>&1
      orca terminal send --terminal "$handle" --enter >/dev/null 2>&1
      orca terminal wait --terminal "$handle" --for tui-idle --timeout-ms 30000 >/dev/null 2>&1
      ;;
  esac
}

# _chief_orca_prompt <handle> <text> - submit <text> to <handle> and wait for
# the TUI to go idle again.
_chief_orca_prompt() {
  local handle=$1 text=$2
  orca terminal send --terminal "$handle" --text "$text" --enter --wait-submit 5 >/dev/null 2>&1 \
    || { echo "chief-backend-orca: 'orca terminal send' failed for $handle" >&2; return 1; }
  orca terminal wait --terminal "$handle" --for tui-idle --timeout-ms 120000 >/dev/null 2>&1
}

# _chief_orca_launch <worktree> <brief_path> -> creates a terminal, starts
# claude, clears the trust dialog, submits the brief; prints the handle.
_chief_orca_launch() {
  local worktree=$1 brief_path=$2
  local json handle
  json=$(orca terminal create --worktree "path:$worktree" --command "claude" --json 2>&1) \
    || { echo "chief-backend-orca: 'orca terminal create' failed: $json" >&2; return 1; }
  handle=$(printf '%s' "$json" | jq -r '.result.handle // .result.terminal.handle // empty')
  [ -n "$handle" ] \
    || { echo "chief-backend-orca: could not read terminal handle from: $json" >&2; return 1; }

  orca terminal wait --terminal "$handle" --for tui-idle --timeout-ms 30000 >/dev/null 2>&1
  _chief_orca_accept_trust_dialog "$handle"
  _chief_orca_prompt "$handle" "$(cat "$brief_path")" || return 1

  printf '%s\n' "$handle"
}

backend_spawn() {
  _chief_orca_warn_once
  local id=$1 project_dir=$2 brief_path=$3 branch=$4
  local worktree="$WORKTREES/$id"
  git -C "$project_dir" worktree add -q -b "$branch" "$worktree" \
    || { echo "chief-backend-orca: 'git worktree add' failed for $id" >&2; return 1; }

  local handle
  handle=$(_chief_orca_launch "$worktree" "$brief_path") || return 1

  printf '%s\n' "$worktree"
  printf 'orca:%s\n' "$handle"
}

backend_send() {
  _chief_orca_warn_once
  local id=$1 text=$2
  local handle
  handle=$(chief_meta_get "$id" endpoint | sed 's/^orca://')
  case "$text" in
    Enter)  orca terminal send --terminal "$handle" --enter ;;
    Escape) orca terminal send --terminal "$handle" --text $'\x1b' ;;
    C-c)    orca terminal send --terminal "$handle" --interrupt ;;
    *)      orca terminal send --terminal "$handle" --text "$text" --enter ;;
  esac >/dev/null 2>&1
}

backend_capture() {
  _chief_orca_warn_once
  local id=$1
  local handle
  handle=$(chief_meta_get "$id" endpoint | sed 's/^orca://')
  orca terminal read --terminal "$handle" --limit 200 --json 2>/dev/null \
    | jq -r '.result.terminal.tail // [] | join("\n")'
}

backend_busy() {
  _chief_orca_warn_once
  local id=$1
  local handle
  handle=$(chief_meta_get "$id" endpoint | sed 's/^orca://')
  # Short idle-wait doubles as a non-blocking poll: succeeds (idle) or
  # times out (busy).
  orca terminal wait --terminal "$handle" --for tui-idle --timeout-ms 200 >/dev/null 2>&1 \
    && return 1
  return 0
}

backend_kill() {
  _chief_orca_warn_once
  local id=$1
  local endpoint handle
  endpoint=$(chief_meta_get "$id" endpoint 2>/dev/null) || return 0
  handle=${endpoint#orca:}
  [ -n "$handle" ] || return 0
  orca terminal close --terminal "$handle" --tab >/dev/null 2>&1 || true
}

backend_relaunch() {
  _chief_orca_warn_once
  local id=$1 brief_path=$2
  local worktree handle
  worktree=$(chief_meta_get "$id" worktree)
  handle=$(_chief_orca_launch "$worktree" "$brief_path") || return 1
  chief_meta_set "$id" endpoint "orca:$handle"
}
