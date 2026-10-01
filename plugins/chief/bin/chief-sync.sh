#!/usr/bin/env bash
# chief-sync.sh - fetch/fast-forward a project's default branch from origin.
# A backend runs this in the project's workspace pane so the sync is visible
# there; <token> lets that caller wait for this particular run to finish.
#
# Usage: chief-sync.sh <project-dir> [token]
. "$(dirname "${BASH_SOURCE[0]}")/lib/git-sync.sh"

[ -n "${1:-}" ] || { echo "usage: chief-sync.sh <project-dir> [token]" >&2; exit 1; }
chief_sync_default_branch "$1"
echo "chief-sync: done ${2:-}"
