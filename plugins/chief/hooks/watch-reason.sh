#!/usr/bin/env bash
# watch-reason.sh <launch-dir> - runs chief-watch.sh for the primary session
# and prints the reason worth waking it, or nothing (nothing in flight, or
# Chief not in use here). Exits 3 inside a spawned builder's own worktree: a
# worker never arms a watcher on itself. Shared by every harness adapter.
set -euo pipefail

CHIEF_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../bin/lib/worktree.sh
. "$CHIEF_PLUGIN_ROOT/bin/lib/worktree.sh"

LAUNCH_DIR="${1:-.}"
chief_is_linked_worktree "$LAUNCH_DIR" && exit 3

# shellcheck source=../bin/lib/home.sh
. "$CHIEF_PLUGIN_ROOT/bin/lib/home.sh"
export CHIEF_HOME="${CHIEF_HOME:-$(cd "$LAUNCH_DIR" && chief_default_home)}"

# shellcheck source=../bin/lib/paths.sh
. "$CHIEF_PLUGIN_ROOT/bin/lib/paths.sh"

# No CHIEF_HOME at all -> Chief isn't in use here; don't create one to watch nothing.
[ -d "$STATE" ] || exit 0

REASON=$("$CHIEF_ROOT/bin/chief-watch.sh" 2>&1) || true

[ -z "$REASON" ] || [ "$REASON" = "nothing in flight" ] || printf '%s\n' "$REASON"
