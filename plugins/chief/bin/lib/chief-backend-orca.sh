#!/usr/bin/env bash
# chief-backend-orca.sh - Orca backend adapter, matched against a live Orca
# CLI (`orca --help` / `orca agent-context --json`, schema v1).
#
# Confirmed live: Orca only resolves a worktree selector (path:/id:/...)
# for a worktree IT created via `orca worktree create` - never one from a
# plain `git worktree add`, even under an already-registered repo. So
# unlike the mock/herdr backends, this can't do its own git worktree add;
# it has to create the worktree through Orca.
#
# `orca worktree create --repo path:<project> --name <id>` has no flag to
# pin an exact branch (only --name, and Orca sanitizes '/' out of it for
# the real branch - "chief/t-1" becomes "chief-t-1"), so backend_spawn
# renames whatever branch Orca picked to the exact "chief/<id>" every
# other chief script expects from meta. The worktree PATH Orca picks is
# left as-is - nothing downstream assumes a fixed path.
#
# Requires the project dir to already be an Orca-registered repo (`orca
# repo list`); this adapter does not try to auto-register it (`orca repo
# add` failed even on an already-registered path in testing - a
# host-targeting quirk, not something to paper over). Fails with a clear
# message pointing at `orca repo add` / importing the project in the app.
#
# `orca terminal create --worktree path:<path>` reliably attaches once the
# worktree exists. Endpoint format: "orca:<terminal-handle>". Sends the
# brief's CONTENT (not its path) as the first prompt - same reason as
# chief-backend-herdr.sh: the brief lives outside the worktree.
#
# busy/idle: `orca terminal wait --for tui-idle --timeout-ms <n>` returns
# ok once idle, or a timeout error while busy - used below as a
# non-blocking poll.
#
# Confirmed live end-to-end (CHIEF_TEST_ORCA=1 tests/chief/test-backend-orca.sh):
# spawn - worktree creation, branch rename, launch, reply capture,
# busy/idle, send, kill - all work.
#
# KNOWN LIVE ISSUE - backend_relaunch: a second `claude` in an
# already-used worktree can land on a different interactive dialog than
# the first-run trust prompt (`orca terminal show` reported the pane
# title as "Session request", empty tail) that
# _chief_orca_accept_trust_dialog doesn't recognize, so the resumed
# prompt never reaches a real turn. Needs more live investigation.
#
# NOT handled: teardown never tells Orca to forget the worktree it
# created (chief-teardown.sh removes worktrees via plain git, same as
# every backend) - a torn-down task can leave a stale Orca worktree
# entry. Would need a new adapter-contract hook for every backend; out of
# scope here.

_chief_orca_warn_relaunch_once() {
  [ -n "${_CHIEF_ORCA_WARNED:-}" ] && return
  _CHIEF_ORCA_WARNED=1
  echo "chief-backend-orca: relaunch has a known live issue - see this file's header" >&2
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
  # orca's connect banner goes to stderr, --json's body to stdout even on
  # failure - discard stderr, don't merge it in (breaks the jq parse below).
  json=$(orca terminal create --worktree "path:$worktree" --command "claude" --json 2>/dev/null) \
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
  local id=$1 project_dir=$2 brief_path=$3 branch=$4
  local json worktree orca_branch
  json=$(orca worktree create --repo "path:$project_dir" --name "$id" --no-parent --json 2>/dev/null) \
    || { echo "chief-backend-orca: 'orca worktree create' failed: $json" >&2
         echo "chief-backend-orca: is '$project_dir' an Orca-registered repo? See 'orca repo list --json' / 'orca repo add --path $project_dir'." >&2
         return 1; }

  worktree=$(printf '%s' "$json" | jq -r '.result.worktree.path // empty')
  orca_branch=$(printf '%s' "$json" | jq -r '.result.worktree.branch // empty' | sed 's#^refs/heads/##')
  [ -n "$worktree" ] && [ -n "$orca_branch" ] \
    || { echo "chief-backend-orca: could not read worktree path/branch from: $json" >&2; return 1; }

  if [ "$orca_branch" != "$branch" ]; then
    git -C "$worktree" branch -m "$branch" \
      || { echo "chief-backend-orca: could not rename branch '$orca_branch' to '$branch' in $worktree" >&2; return 1; }
  fi

  local handle
  handle=$(_chief_orca_launch "$worktree" "$brief_path") || return 1

  printf '%s\n' "$worktree"
  printf 'orca:%s\n' "$handle"
}

backend_send() {
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
  local id=$1
  local handle
  handle=$(chief_meta_get "$id" endpoint | sed 's/^orca://')
  orca terminal read --terminal "$handle" --limit 200 --json 2>/dev/null \
    | jq -r '.result.terminal.tail // [] | join("\n")'
}

backend_busy() {
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
  local id=$1
  local endpoint handle
  endpoint=$(chief_meta_get "$id" endpoint 2>/dev/null) || return 0
  handle=${endpoint#orca:}
  [ -n "$handle" ] || return 0
  orca terminal close --terminal "$handle" --tab >/dev/null 2>&1 || true
}

backend_relaunch() {
  _chief_orca_warn_relaunch_once
  local id=$1 brief_path=$2
  local worktree handle
  worktree=$(chief_meta_get "$id" worktree)
  handle=$(_chief_orca_launch "$worktree" "$brief_path") || return 1
  chief_meta_set "$id" endpoint "orca:$handle"
}
