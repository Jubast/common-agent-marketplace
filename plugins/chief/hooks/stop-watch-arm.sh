#!/usr/bin/env bash
# stop-watch-arm.sh - the token-saving trick. Registered as a Stop hook with
# asyncRewake: true, so Claude Code runs this in the background at zero
# model cost every time the primary session's turn ends, and only "rewakes"
# the session (via exit 2 + stderr) if it finds something worth interrupting
# you for. chief-watch.sh does the actual polling; this script only
# interprets its exit.
#
# Deliberately NOT handled here (kept out for v1 simplicity): concurrent-arm
# locking, generation claims, beacon staleness backstops. Firstmate's
# equivalent (bin/fm-claude-stop-autoarm.sh) solves those; this is the
# simpler version of the same idea, sized for one person's fleet.
set -euo pipefail

CHIEF_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$CHIEF_PLUGIN_ROOT/bin/chief-watch.sh"
# shellcheck source=../bin/lib/chief-worktree.sh
. "$CHIEF_PLUGIN_ROOT/bin/lib/chief-worktree.sh"

# A spawned builder's own session must never arm a watcher on itself - only
# the primary (operator-facing) session supervises. This check is race-free
# even against Orca's create-and-launch-in-one-call spawn; see
# bin/lib/chief-worktree.sh.
chief_is_linked_worktree && exit 0

# No CHIEF_HOME at all -> Chief isn't in use here; let the
# turn end normally rather than creating one just to watch nothing.
_chief_home="${CHIEF_HOME:-}"
if [ -z "$_chief_home" ]; then
  _git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  _chief_home="${_git_root:-$(pwd)}/.chief"
fi
[ -d "$_chief_home/state" ] || exit 0

REASON=$("$WATCH" 2>&1) || true

if [ "$REASON" = "nothing in flight" ]; then
  exit 0
fi

echo "chief watcher: $REASON" >&2
exit 2
