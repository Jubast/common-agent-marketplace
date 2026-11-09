#!/usr/bin/env bash
# stop-watch-codex.sh - Codex's wake adapter (async Stop hook): `codex queue`s the
# watcher's reason only while a Codex TUI runs in the cwd, else it would run headless.
set -euo pipefail

SESSION=$(jq -r '.session_id // empty')
[ -n "$SESSION" ] || exit 0

REASON=$("$(dirname "${BASH_SOURCE[0]}")/watch-reason.sh" .) || exit 0
[ -n "$REASON" ] || exit 0

tui_alive() {
  local p cwd
  [ -d /proc/$$ ] || return 0  # no /proc: cannot tell, assume alive
  cwd=$(pwd -P)
  for p in $(pgrep -x codex); do
    [ "$(readlink "/proc/$p/cwd" 2>/dev/null)" = "$cwd" ] || continue
    tr '\0' ' ' < "/proc/$p/cmdline" | grep -qE ' (app-server|queue)( |$)' && continue
    return 0
  done
  return 1
}
tui_alive || exit 0

codex queue --thread "$SESSION" --message "chief watcher: $REASON" >/dev/null 2>&1 || true
