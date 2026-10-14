#!/usr/bin/env bash
# paths.sh - shared path resolution, sourced by every chief-*.sh entrypoint.
#
# Two roots, never confused:
#   CHIEF_ROOT  the plugin's own installed files (bin/, templates/, skills/) -
#               read-only, resolved from this script's own location so it
#               works whether Claude Code installed the plugin or a developer
#               is running it straight out of a checkout.
#   CHIEF_HOME  the operator's one shared runtime home: tasks/<id>/ (one folder
#               per task), archive/ (torn-down tasks), state/ (global locks,
#               cursors, heartbeat), data/backlog.md, config/, worktrees/.
#               Defaults to <outermost git root>/.chief of wherever the
#               Chief session runs (never inside a project - see home.sh),
#               override with the CHIEF_HOME env var. This is gitignored
#               working state, never plugin code.
#
# Every bin/chief-*.sh entrypoint sources this before anything else, relative
# to its own directory - "lib/paths.sh" from bin/, "../lib/paths.sh" from
# bin/task/ or bin/pr/.

# This file always lives at <plugin-root>/bin/lib/paths.sh, so its own
# location - not the caller's - is what tells us where the plugin root is.
_chief_paths_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHIEF_ROOT="${CHIEF_ROOT_OVERRIDE:-$(cd "$_chief_paths_lib_dir/../.." && pwd)}"
. "$_chief_paths_lib_dir/home.sh"

CHIEF_HOME="${CHIEF_HOME:-$(chief_default_home)}"

TASKS="$CHIEF_HOME/tasks"
ARCHIVE="$CHIEF_HOME/archive"
STATE="$CHIEF_HOME/state"
DATA="$CHIEF_HOME/data"
CONFIG="$CHIEF_HOME/config"
WORKTREES="$CHIEF_HOME/worktrees"

mkdir -p "$TASKS" "$STATE" "$DATA" "$CONFIG" "$WORKTREES"

. "$_chief_paths_lib_dir/meta.sh"
unset _chief_paths_lib_dir
