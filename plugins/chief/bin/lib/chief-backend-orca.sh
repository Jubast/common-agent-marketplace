#!/usr/bin/env bash
# chief-backend-orca.sh - DRAFT, UNVERIFIED. Orca is a desktop app (Electron);
# its CLI talks to a running instance, which this development sandbox does
# not have, so none of the commands below have been run for real.
#
# Confirmed from Orca's own documented interface (plugins/using-orca):
#   orca worktree create --agent <agent-id> --prompt "<task>" --json
#   orca status --json
# Everything else here (send/capture/busy/kill) is a best-guess shape that
# MUST be checked against `orca --help` / `orca worktree --help` against a
# live Orca instance before this adapter is trusted with real work.
#
# TODO before first real use:
#   - confirm the exact subcommand for sending text/keys to a worktree's
#     terminal (guessed: `orca terminal send`)
#   - confirm how to read a terminal's current output (guessed: `orca
#     terminal capture` / `orca worktree show --json`)
#   - confirm the busy/idle signal Orca itself exposes, if any
#   - confirm the terminal teardown command (guessed: `orca terminal close`)
#   - confirm --json output field names actually used below (worktree.path,
#     worktree.id) against a real response

_chief_orca_warn_once() {
  [ -n "${_CHIEF_ORCA_WARNED:-}" ] && return
  _CHIEF_ORCA_WARNED=1
  echo "chief-backend-orca: DRAFT adapter, unverified against a live Orca instance - see this file's header" >&2
}

backend_spawn() {
  _chief_orca_warn_once
  local id=$1 project_dir=$2 brief_path=$3 branch=$4
  local prompt
  prompt="Read and follow the brief at $brief_path."
  local json
  json=$(orca worktree create --agent claude --prompt "$prompt" --branch "$branch" --cwd "$project_dir" --json) \
    || { echo "chief-backend-orca: 'orca worktree create' failed" >&2; return 1; }
  local worktree_path worktree_id
  worktree_path=$(printf '%s' "$json" | jq -r '.worktree.path // .path')
  worktree_id=$(printf '%s' "$json" | jq -r '.worktree.id // .id')
  [ -n "$worktree_path" ] && [ "$worktree_path" != "null" ] \
    || { echo "chief-backend-orca: could not read worktree path from: $json" >&2; return 1; }
  printf '%s\n' "$worktree_path"
  printf 'orca:%s\n' "$worktree_id"
}

backend_send() {
  _chief_orca_warn_once
  local id=$1 text=$2
  local worktree_id
  worktree_id=$(chief_meta_get "$id" endpoint | sed 's/^orca://')
  orca terminal send --worktree "$worktree_id" --text "$text" >/dev/null
}

backend_capture() {
  _chief_orca_warn_once
  local id=$1
  local worktree_id
  worktree_id=$(chief_meta_get "$id" endpoint | sed 's/^orca://')
  orca terminal capture --worktree "$worktree_id"
}

backend_busy() {
  _chief_orca_warn_once
  local id=$1
  local worktree_id
  worktree_id=$(chief_meta_get "$id" endpoint | sed 's/^orca://')
  local json
  json=$(orca status --json) || return 1
  printf '%s' "$json" | jq -e --arg w "$worktree_id" \
    '.worktrees[]? | select(.id == $w) | .busy == true' >/dev/null
}

backend_kill() {
  _chief_orca_warn_once
  local id=$1
  local worktree_id
  worktree_id=$(chief_meta_get "$id" endpoint | sed 's/^orca://')
  orca terminal close --worktree "$worktree_id" >/dev/null 2>&1 || true
}

backend_relaunch() {
  _chief_orca_warn_once
  local id=$1 brief_path=$2
  local worktree_id
  worktree_id=$(chief_meta_get "$id" endpoint | sed 's/^orca://')
  local prompt="Read and follow the brief at $brief_path."
  orca terminal open --worktree "$worktree_id" --agent claude --prompt "$prompt" >/dev/null \
    || { echo "chief-backend-orca: relaunch 'orca terminal open' failed" >&2; return 1; }
}
