#!/usr/bin/env bash
# chief-paths.sh - shared path resolution, sourced by every chief-*.sh entrypoint.
#
# Two roots, never confused:
#   CHIEF_ROOT  the plugin's own installed files (bin/, templates/, skills/) -
#               read-only, resolved from this script's own location so it
#               works whether Claude Code installed the plugin or a developer
#               is running it straight out of a checkout.
#   CHIEF_HOME  the operator's one shared runtime home (state/, data/) -
#               resolved from the git root of wherever the Chief session
#               itself runs, not per-project; defaults to <repo-root>/.chief,
#               override with the CHIEF_HOME env var. This is gitignored
#               working state, never plugin code.
#
# Every top-level bin/chief-*.sh script sources this before anything else:
#   . "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"

# This file always lives at <plugin-root>/bin/lib/chief-paths.sh, so its own
# location - not the caller's - is what tells us where the plugin root is.
_chief_paths_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHIEF_ROOT="${CHIEF_ROOT_OVERRIDE:-$(cd "$_chief_paths_lib_dir/../.." && pwd)}"
unset _chief_paths_lib_dir

if [ -z "${CHIEF_HOME:-}" ]; then
  _chief_git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  CHIEF_HOME="${_chief_git_root:-$(pwd)}/.chief"
  unset _chief_git_root
fi

STATE="$CHIEF_HOME/state"
DATA="$CHIEF_HOME/data"
CONFIG="$CHIEF_HOME/config"
WORKTREES="$CHIEF_HOME/worktrees"

mkdir -p "$STATE" "$DATA" "$CONFIG" "$WORKTREES"
