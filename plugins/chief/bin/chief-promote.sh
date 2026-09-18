#!/usr/bin/env bash
# chief-promote.sh - convert a scout into a ship task in place: same id,
# same worktree, same branch, same running agent. Flips mode=scout to
# mode=ship in meta and delivers the new ship intent/spec through the
# ordinary steering inbox (chief-send.sh) - the same channel used for any
# other mid-task instruction, so no new delivery mechanism is needed. Also
# appends the same notice to brief.md so a later relaunch still gets ship
# instructions instead of the original scout brief.
#
# Usage: chief-promote.sh <id> --intent "<operator's ask>" [--spec "..."]
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"

fail() { echo "chief-promote: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-promote.sh <id> --intent \"...\" [--spec \"...\"]"
shift

INTENT=""
SPEC="(none given - use your own judgement within the intent above.)"
while [ $# -gt 0 ]; do
  case "$1" in
    --intent) INTENT=$2; shift 2 ;;
    --spec) SPEC=$2; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[ -n "$INTENT" ] || fail "--intent is required"

chief_meta_exists "$ID" || fail "no such task: $ID"
[ "$(chief_meta_get "$ID" mode)" = "scout" ] || fail "$ID is not a scout (already promoted, or a ship task)"

BRANCH=$(chief_meta_require "$ID" branch)
REPORT="$DATA/$ID/report.md"

# %s placeholders, filled by printf below - never shell-interpolated, so
# nothing in $INTENT or $SPEC can be misread as a substitution or command.
read -r -d '' NOTICE_FMT <<'EOF' || true

# Promoted to a ship task (%s)
You are no longer a scout. This task is now a ship task: the deliverable is a commit on your branch `%s`, ready for review - not a report.

## Operator's intent
%s

## Chief's spec
%s

Your earlier findings at %s are context, not the deliverable. Carry over only the changes this intent actually needs - leave scratch commits and throwaway edits behind. Stay inside this worktree; never push, never open a PR, never merge - Chief does that after review. Report status the same way as before (working/needs-decision/blocked/done/failed), but `done` now means the commit is ready, not that the report is finished. Follow the `reviewer` skill's checklist against your own diff before reporting done.
EOF

NOTICE=$(printf "$NOTICE_FMT" "$(date -u +%Y-%m-%dT%H:%MZ)" "$BRANCH" "$INTENT" "$SPEC" "$REPORT")

printf '%s\n' "$NOTICE" >> "$DATA/$ID/brief.md"
"$CHIEF_ROOT/bin/chief-send.sh" "$ID" "$NOTICE"

chief_meta_set "$ID" mode ship
"$CHIEF_ROOT/bin/chief-backlog.sh" note "$ID" "promoted from scout to ship" 2>/dev/null || true

echo "promoted: $ID (scout -> ship) in place, instructions sent"
