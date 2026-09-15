#!/usr/bin/env bash
# chief-backend-herdr.sh - DRAFT, UNVERIFIED. herdr is not installed in this
# development sandbox, so nothing below has been run against the real tool.
#
# What's known secondhand (not confirmed live): herdr manages named sessions,
# a session name plus a trailing `--session <name>` is required on most
# calls, and its API socket is not relocatable by env vars. Nothing about
# its worktree-creation, send-keys, capture, or teardown subcommands is
# confirmed - the command names below are placeholders, not verified syntax.
#
# TODO before first real use: replace every command below with the real
# subcommands from `herdr --help` / `herdr session --help` against an
# installed herdr, including exact flag names and --json output shape.

_chief_herdr_warn_once() {
  [ -n "${_CHIEF_HERDR_WARNED:-}" ] && return
  _CHIEF_HERDR_WARNED=1
  echo "chief-backend-herdr: DRAFT adapter, unverified - herdr is not installed here, see this file's header" >&2
}

_chief_herdr_session() {
  echo "chief-$1"
}

backend_spawn() {
  _chief_herdr_warn_once
  local id=$1 project_dir=$2 brief_path=$3 branch=$4
  local session
  session=$(_chief_herdr_session "$id")
  local worktree="$WORKTREES/$id"
  git -C "$project_dir" worktree add -q -b "$branch" "$worktree" >/dev/null
  herdr session create --session "$session" --cwd "$worktree" \
    --command "claude \"$brief_path\"" >/dev/null \
    || { echo "chief-backend-herdr: 'herdr session create' failed" >&2; return 1; }
  printf '%s\n' "$worktree"
  printf 'herdr:%s\n' "$session"
}

backend_send() {
  _chief_herdr_warn_once
  local id=$1 text=$2
  local session
  session=$(_chief_herdr_session "$id")
  herdr session send-keys --session "$session" --text "$text" >/dev/null
}

backend_capture() {
  _chief_herdr_warn_once
  local id=$1
  local session
  session=$(_chief_herdr_session "$id")
  herdr session capture --session "$session"
}

backend_busy() {
  _chief_herdr_warn_once
  local id=$1
  local session
  session=$(_chief_herdr_session "$id")
  herdr session status --session "$session" --json | jq -e '.busy == true' >/dev/null
}

backend_kill() {
  _chief_herdr_warn_once
  local id=$1
  local session
  session=$(_chief_herdr_session "$id")
  herdr session stop --session "$session" >/dev/null 2>&1 || true
  herdr session delete --session "$session" >/dev/null 2>&1 || true
}

backend_relaunch() {
  _chief_herdr_warn_once
  local id=$1 brief_path=$2
  local session worktree
  session=$(_chief_herdr_session "$id")
  worktree=$(chief_meta_get "$id" worktree)
  herdr session create --session "$session" --cwd "$worktree" \
    --command "claude \"$brief_path\"" >/dev/null \
    || { echo "chief-backend-herdr: relaunch 'herdr session create' failed" >&2; return 1; }
}
