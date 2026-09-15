#!/usr/bin/env bash
# chief-backend-mock.sh - DEV/TEST ONLY fake terminal backend.
#
# Real backends launch `claude` in a real terminal. This one launches a
# harmless placeholder background process instead, so the rest of Chief's
# scripts (spawn/control/crew-state/watch/teardown) can be exercised end to
# end without herdr, Orca, or spending real model tokens. A test then plays
# the builder's role by hand-writing state/<id>.status and
# state/<id>.turn-ended, exactly as a real brief instructs a real agent to.
#
# "Terminal" here is one log file (state/<id>.term.log) plus one long-lived
# placeholder process whose pid is recorded in state/<id>.term.pid.

backend_spawn() {
  local id=$1 project_dir=$2 brief_path=$3 branch=$4
  local worktree="$WORKTREES/$id"
  git -C "$project_dir" worktree add -q -b "$branch" "$worktree" >/dev/null
  local log="$STATE/$id.term.log"
  : > "$log"
  {
    echo "[mock] launched for $id"
    echo "[mock] brief: $brief_path"
    echo "[mock] worktree: $worktree"
  } >> "$log"
  # A placeholder long-lived process standing in for a real terminal session.
  # Must not inherit this function's stdout/stderr: backend_spawn's caller
  # reads its output via $(...), and a background child holding that pipe's
  # write end open would block the command substitution until the child
  # exits - i.e. until sleep's 100000 seconds are up.
  ( exec -a "chief-mock-$id" sleep 100000 ) >/dev/null 2>&1 &
  disown
  echo $! > "$STATE/$id.term.pid"
  printf '%s\n' "$worktree"
  printf 'mock:%s\n' "$id"
}

backend_send() {
  local id=$1 text=$2
  echo "[mock] send: $text" >> "$STATE/$id.term.log"
}

backend_capture() {
  local id=$1
  cat "$STATE/$id.term.log" 2>/dev/null
}

backend_busy() {
  local id=$1
  local pid
  pid=$(cat "$STATE/$id.term.pid" 2>/dev/null) || return 1
  kill -0 "$pid" 2>/dev/null
}

backend_relaunch() {
  local id=$1 brief_path=$2
  echo "[mock] relaunch for $id" >> "$STATE/$id.term.log"
  echo "[mock] brief: $brief_path" >> "$STATE/$id.term.log"
  ( exec -a "chief-mock-$id" sleep 100000 ) >/dev/null 2>&1 &
  disown
  echo $! > "$STATE/$id.term.pid"
}

backend_kill() {
  local id=$1
  local pid
  pid=$(cat "$STATE/$id.term.pid" 2>/dev/null) || return 0
  kill "$pid" 2>/dev/null || true
  rm -f "$STATE/$id.term.pid" "$STATE/$id.term.log"
}
