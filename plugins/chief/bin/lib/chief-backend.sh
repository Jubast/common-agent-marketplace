#!/usr/bin/env bash
# chief-backend.sh - loads the configured backend adapter and nothing else.
# Every chief-*.sh script that needs a worker terminal sources this (after
# chief-paths.sh AND chief-meta.sh - the herdr/orca adapters call
# chief_meta_get to recover their own endpoint identifier); nothing above
# this file should know whether it's talking to herdr or Orca.
#
# Adapter contract - each backend-<name>.sh must define all five:
#   backend_spawn   <id> <project-dir> <brief-path> <branch>
#                     -> creates the worktree + terminal, launches claude in
#                        it pointed at the brief, prints the worktree path on
#                        its own stdout line first, then the backend's own
#                        endpoint identifier on a second line.
#   backend_send    <id> <text-or-special-key>
#                     -> best-effort delivers text (or "Enter"/"Escape"/"C-c")
#                        to that task's terminal.
#   backend_capture <id> -> prints the terminal's current visible output.
#   backend_busy    <id> -> exit 0 if the terminal looks actively working,
#                           exit 1 if idle/settled. Best-effort; chief-watch.sh
#                           treats state/<id>.turn-ended as the authoritative
#                           signal and this as a fallback only.
#   backend_kill    <id> -> tears down the terminal/session. Never touches
#                           the worktree or its git history.
#   backend_relaunch <id> <brief-path>
#                     -> launches a fresh claude in the EXISTING worktree
#                        (recorded in state/<id>.meta) pointed at the given
#                        brief, after backend_kill already stopped the old
#                        one. Does not create a new worktree or branch.
#
# Selection: $CHIEF_BACKEND env var, else $CONFIG/backend, else "herdr".

CHIEF_BACKEND="${CHIEF_BACKEND:-}"
if [ -z "$CHIEF_BACKEND" ] && [ -f "$CONFIG/backend" ]; then
  CHIEF_BACKEND=$(tr -d '[:space:]' < "$CONFIG/backend")
fi
CHIEF_BACKEND="${CHIEF_BACKEND:-herdr}"

case "$CHIEF_BACKEND" in
  herdr|orca) ;;
  mock)
    # Dev/test only - a fake terminal (one background process + a log file)
    # used to exercise chief-spawn/control/crew-state/watch without a real
    # herdr or Orca install. Never select this in a real project.
    ;;
  *)
    echo "chief-backend: unsupported backend '$CHIEF_BACKEND' (must be herdr or orca)" >&2
    exit 1
    ;;
esac

# shellcheck source=/dev/null
. "$CHIEF_ROOT/bin/lib/chief-backend-$CHIEF_BACKEND.sh"
