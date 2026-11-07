#!/usr/bin/env bash
# stop-watch-arm.sh - the token-saving trick. Registered as a Stop hook with
# asyncRewake: true, so Claude Code runs this in the background at zero
# model cost every time the primary session's turn ends, and only "rewakes"
# the session (via exit 2 + stderr) if it finds something worth interrupting
# you for. watch-reason.sh does the actual watching; this script only
# interprets its output.
#
# Concurrent arms are resolved by chief-watch.sh itself (the newest watcher
# takes over; an older one exits silently, which this script must not rewake
# on). Beacon staleness backstops are deliberately not handled.
set -euo pipefail

# Codex and Copilot set PLUGIN_ROOT and have their own wake adapters.
[ -z "${PLUGIN_ROOT:-}" ] || exit 0

# Judge by the launch dir, not the cwd, which drifts in the primary session.
REASON=$("$(dirname "${BASH_SOURCE[0]}")/watch-reason.sh" "${CLAUDE_PROJECT_DIR:-.}") || exit 0

[ -n "$REASON" ] || exit 0

echo "chief watcher: $REASON" >&2
exit 2
