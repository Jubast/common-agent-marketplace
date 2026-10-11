#!/usr/bin/env bash
# chief-promote.sh - hand a done researcher or brainstormer off to a successor
# worker (chief-spawn.sh --from), then retire the source. The successor runs the
# --to role's configured agent, not the source's; pass --agent to override.
#
# Usage: chief-promote.sh <id> --to <role> --branch <name> --intent "..." \
#          [--as <new-id>] [--keep-source] [--dry-run] [--spec/--agent/--model/--args ...]
# <new-id> defaults to <id>-<role> and must already be filed in the backlog.
# --keep-source leaves the source running; --dry-run prints the agent and
# launch line only. Other flags go to chief-spawn.sh.
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/../lib/paths.sh"
. "$CHIEF_ROOT/bin/lib/meta.sh"

fail() { echo "chief-promote: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-promote.sh <id> --to <role> --branch <name> --intent \"...\" [--as <new-id>] [--keep-source] [--dry-run] [spawn flags]"
shift
TO="" NEW="" KEEP=0 DRY=0 REST=()
while [ $# -gt 0 ]; do
  case "$1" in
    --to) TO=$2; shift 2 ;;
    --as) NEW=$2; shift 2 ;;
    --keep-source) KEEP=1; shift ;;
    --mode|--from) fail "$1 is set by chief-promote.sh (use --to)" ;;
    --dry-run) DRY=1; REST+=("$1"); shift ;;
    *) REST+=("$1"); shift ;;
  esac
done
[ -n "$TO" ] || fail "--to <role> is required"

NEW=${NEW:-$ID-$TO}
PROJECT=$(chief_meta_require "$ID" project)
[ "$DRY" -eq 1 ] || [ -n "$("$CHIEF_ROOT/bin/chief-backlog.sh" show "$NEW")" ] || fail "$NEW is not in the backlog - file it first (chief-backlog.sh add)"
"$CHIEF_ROOT/bin/chief-spawn.sh" "$NEW" "$PROJECT" --mode "$TO" --from "$ID" "${REST[@]}"
[ "$DRY" -eq 1 ] || [ "$KEEP" -eq 1 ] || "$CHIEF_ROOT/bin/chief-teardown.sh" "$ID" || fail "$NEW is running but tearing down $ID failed"
