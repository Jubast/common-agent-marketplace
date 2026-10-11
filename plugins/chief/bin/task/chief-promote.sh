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
    --dry-run) DRY=1; REST+=("$1"); shift ;;
    *) REST+=("$1"); shift ;;
  esac
done
[ -n "$TO" ] || fail "--to <role> is required"

PROJECT=$(chief_meta_require "$ID" project)
"$CHIEF_ROOT/bin/chief-spawn.sh" "${NEW:-$ID-$TO}" "$PROJECT" --mode "$TO" --from "$ID" "${REST[@]}"
[ "$DRY" -eq 1 ] || [ "$KEEP" -eq 1 ] || "$CHIEF_ROOT/bin/chief-teardown.sh" "$ID"
