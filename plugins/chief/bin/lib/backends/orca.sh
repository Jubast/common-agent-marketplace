#!/usr/bin/env bash
# orca.sh - Orca backend adapter (`orca agent-context --json`, schema v1).
#
# Same flow as herdr.sh: each task gets its own linked worktree plus a
# terminal running claude, started in bypass-permissions mode (dispatched
# workers are unattended - nobody is present to answer a permission dialog),
# given the brief's CONTENT as its first prompt (the brief lives outside the
# worktree), and cleaned up on any failure.
#
# Orca only resolves a worktree selector for a worktree IT created, so
# backend_spawn goes through `orca worktree create --repo path:<project>`
# (the project must already be in `orca repo list`; `orca repo add` is not
# attempted). That call can't pin a branch or path: Orca sanitizes '/' out
# of --name for the branch, which is renamed to the exact requested one, and
# the path Orca picks is used as-is.
#
# Endpoint: "orca:<terminal-handle>". backend_busy polls `orca terminal
# wait --for tui-idle` with a short timeout.
#
# backend_kill closes every terminal in the task's worktree (herdr closes the
# whole workspace). backend_teardown also tells Orca to forget the worktree,
# which plain `git worktree remove` would leave as a stale entry.
#
# Known live issue: backend_relaunch in an already-used worktree can land on
# a dialog other than the trust prompt (pane title "Session request") that
# _chief_orca_accept_trust_dialog doesn't recognize.

_chief_orca_warn_relaunch_once() {
  [ -n "${_CHIEF_ORCA_WARNED:-}" ] && return
  _CHIEF_ORCA_WARNED=1
  echo "chief-backend-orca: relaunch has a known live issue - see this file's header" >&2
}

_chief_orca_handle() {  # <id> -> the task's terminal handle
  chief_meta_get "$1" endpoint | sed 's/^orca://'
}

_chief_orca_close_tab() {  # <handle> - best-effort
  orca terminal close --terminal "$1" --tab >/dev/null 2>&1 || true
}

# _chief_orca_find_worktree <id> <project-dir> <branch> - prints
# "<path>\t<refs/heads/branch>" of the Orca worktree backend_spawn made for
# <id>: on the requested branch, or still on Orca's own sanitized-name branch
# if the rename never happened. The only id-derived handle that survives a
# failed spawn with no meta record.
_chief_orca_find_worktree() {
  local id=$1 project_dir=$2 branch=$3 name=${1//\//-}
  orca worktree list --repo "path:$project_dir" --json 2>/dev/null \
    | jq -r --arg b "refs/heads/$branch" --arg n "refs/heads/$name" --arg s "/$name" \
        '.result.worktrees[]? | select(.branch == $b or (.branch == $n and (.path | endswith($s)))) | "\(.path)\t\(.branch)"' \
    | head -n1
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

# _chief_orca_prompt <handle> <text> - submit <text> to <handle> and confirm
# it was accepted. Does NOT wait for the resulting turn to go idle - a
# first turn on a large task can legitimately run for a long time, and
# backend_spawn only needs to know the prompt landed, same as backend_send.
_chief_orca_prompt() {
  local handle=$1 text=$2
  orca terminal send --terminal "$handle" --text "$text" --enter --wait-submit 5 >/dev/null 2>&1 \
    || { echo "chief-backend-orca: 'orca terminal send' failed for $handle" >&2; return 1; }
}

# _chief_orca_launch <worktree> <brief_path> -> creates a terminal, starts
# claude, clears the trust dialog, submits the brief; prints the handle.
# Closes the new terminal if the brief can't be delivered.
_chief_orca_launch() {
  local worktree=$1 brief_path=$2
  local json handle
  # orca's connect banner goes to stderr, --json's body to stdout even on
  # failure - discard stderr, don't merge it in (breaks the jq parse below).
  json=$(orca terminal create --worktree "path:$worktree" --command "claude --dangerously-skip-permissions" --json 2>/dev/null) \
    || { echo "chief-backend-orca: 'orca terminal create' failed: $json" >&2; return 1; }
  handle=$(printf '%s' "$json" | jq -r '.result.handle // .result.terminal.handle // empty')
  [ -n "$handle" ] \
    || { echo "chief-backend-orca: could not read terminal handle from: $json" >&2; return 1; }

  orca terminal wait --terminal "$handle" --for tui-idle --timeout-ms 30000 >/dev/null 2>&1
  _chief_orca_accept_trust_dialog "$handle"
  _chief_orca_prompt "$handle" "$(cat "$brief_path")" || { _chief_orca_close_tab "$handle"; return 1; }

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

# backend_spawn_cleanup <id> <project-dir> <branch> - best-effort rollback
# after backend_spawn itself failed, or chief-spawn.sh couldn't parse its
# output. See backend.sh's contract header for the calling convention.
backend_spawn_cleanup() {
  local id=$1 project_dir=$2 branch=$3
  local found worktree orca_branch
  found=$(_chief_orca_find_worktree "$id" "$project_dir" "$branch")
  [ -n "$found" ] || return 0
  worktree=${found%%$'\t'*}
  orca_branch=${found#*$'\t'}
  orca_branch=${orca_branch#refs/heads/}
  orca terminal close --worktree "path:$worktree" --all >/dev/null 2>&1 || true
  orca worktree rm --worktree "path:$worktree" --force >/dev/null 2>&1 \
    || git -C "$project_dir" worktree remove --force "$worktree" >/dev/null 2>&1 \
    || rm -rf "$worktree"
  git -C "$project_dir" branch -D "$branch" >/dev/null 2>&1 || true
  git -C "$project_dir" branch -D "$orca_branch" >/dev/null 2>&1 || true
}

backend_send() {
  local id=$1 text=$2
  local handle
  handle=$(_chief_orca_handle "$id")
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
  handle=$(_chief_orca_handle "$id")
  orca terminal read --terminal "$handle" --limit 200 --json 2>/dev/null \
    | jq -r '.result.terminal.tail // [] | join("\n")'
}

backend_busy() {
  local id=$1
  local handle
  handle=$(_chief_orca_handle "$id")
  # Short idle-wait doubles as a non-blocking poll: succeeds (idle) or
  # times out (busy).
  orca terminal wait --terminal "$handle" --for tui-idle --timeout-ms 200 >/dev/null 2>&1 \
    && return 1
  return 0
}

backend_kill() {
  local id=$1
  local endpoint worktree
  endpoint=$(chief_meta_get "$id" endpoint 2>/dev/null) || return 0
  [ -n "${endpoint#orca:}" ] || return 0
  worktree=$(chief_meta_get "$id" worktree 2>/dev/null) || worktree=""
  if [ -n "$worktree" ]; then
    orca terminal close --worktree "path:$worktree" --all >/dev/null 2>&1 || true
  else
    _chief_orca_close_tab "${endpoint#orca:}"
  fi
}

# backend_teardown <id> <project-dir> <worktree> - optional hook, called by
# chief-teardown.sh after backend_kill and before it removes the worktree
# via git.
backend_teardown() {
  orca worktree rm --worktree "path:$3" --force >/dev/null 2>&1 || true
}

backend_relaunch() {
  _chief_orca_warn_relaunch_once
  local id=$1 brief_path=$2
  local worktree handle
  worktree=$(chief_meta_get "$id" worktree)
  handle=$(_chief_orca_launch "$worktree" "$brief_path") || return 1
  chief_meta_set "$id" endpoint "orca:$handle"
}
