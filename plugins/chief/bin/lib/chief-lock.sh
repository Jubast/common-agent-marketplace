#!/usr/bin/env bash
# chief-lock.sh - a directory-based mutex. `mkdir` is atomic on every POSIX
# filesystem, which is the whole reason this needs no flock/fcntl dependency.
#
# chief_lock_acquire <lock-dir> [timeout-seconds, default 10]
#   Returns 0 once acquired, 1 on timeout. Stores the winning shell's PID
#   inside the lock dir so a leftover lock from a dead process is visible.
# chief_lock_release <lock-dir>

chief_lock_acquire() {
  local dir=$1
  local timeout=${2:-10}
  local waited=0
  while ! mkdir "$dir" 2>/dev/null; do
    if [ -f "$dir/pid" ]; then
      local holder
      holder=$(cat "$dir/pid" 2>/dev/null || true)
      if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
        echo "chief-lock: removing stale lock $dir (dead pid $holder)" >&2
        rm -rf "$dir"
        continue
      fi
    fi
    [ "$waited" -ge "$timeout" ] && return 1
    sleep 1
    waited=$((waited + 1))
  done
  echo $$ > "$dir/pid"
  return 0
}

chief_lock_release() {
  rm -rf "$1"
}
