#!/usr/bin/env bash
# chief-spawn.sh - render a brief, create a worktree+terminal via the
# configured backend, launch the builder, record its meta.
#
# Usage: chief-spawn.sh <id> <project-dir> --mode ship|scout \
#                        --intent "<operator's ask>" [--spec "<build instructions>"]
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"
. "$CHIEF_ROOT/bin/lib/chief-backend.sh"

fail() { echo "chief-spawn: $*" >&2; exit 1; }

ID=${1:-}; PROJECT=${2:-}
[ -n "$ID" ] && [ -n "$PROJECT" ] || fail "usage: chief-spawn.sh <id> <project-dir> --mode ship|scout --intent \"...\" [--spec \"...\"]"
shift 2
[ -d "$PROJECT" ] || fail "no such project directory: $PROJECT"
chief_meta_exists "$ID" && fail "task $ID already has a meta record - use a fresh id"

# Atomic spawn lock: guards the window between the chief_meta_exists check
# above and chief_meta_set below (meta isn't written until backend_spawn
# has fully succeeded) - without it, a second chief-spawn.sh for the same
# id (accidental double-dispatch, a naive retry wrapper) would pass the
# same check and race this one's backend_spawn/backend_spawn_cleanup over
# the same worktree path/branch/pane label. `set -C` (noclobber) makes the
# create-if-absent atomic; the trap releases it on any exit, success or
# failure.
LOCK="$STATE/.$ID.spawning"
( set -C; : > "$LOCK" ) 2>/dev/null || fail "task $ID is already being spawned (lock $LOCK exists)"
trap 'rm -f "$LOCK"' EXIT

MODE=""
INTENT=""
SPEC="(none given - use your own judgement within the intent above.)"
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE=$2; shift 2 ;;
    --intent) INTENT=$2; shift 2 ;;
    --spec) SPEC=$2; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
case "$MODE" in
  ship|scout) ;;
  *) fail "--mode must be ship or scout" ;;
esac
[ -n "$INTENT" ] || fail "--intent is required"

BRANCH="chief/$ID"
mkdir -p "$DATA/$ID"
BRIEF="$DATA/$ID/brief.md"
STATUS_FILE="$STATE/$ID.status"
INBOX_DIR="$STATE/$ID.inbox"
REPORT_FILE="$DATA/$ID/report.md"
mkdir -p "$INBOX_DIR/handled"
: > "$STATUS_FILE"

TEMPLATE="$CHIEF_ROOT/templates/brief-$MODE.md"
[ -f "$TEMPLATE" ] || fail "no template for mode $MODE at $TEMPLATE"

# Plain sed substitution, not a heredoc generator - the template is the only
# source of truth for a brief's prose; this script only fills placeholders.
sed \
  -e "s|{TASK}|$INTENT|g" \
  -e "s|{SPEC}|$SPEC|g" \
  -e "s|{BRANCH}|$BRANCH|g" \
  -e "s|{STATUS_FILE}|$STATUS_FILE|g" \
  -e "s|{INBOX_DIR}|$INBOX_DIR|g" \
  -e "s|{REPORT_FILE}|$REPORT_FILE|g" \
  "$TEMPLATE" > "$BRIEF"

# backend_spawn prints exactly two lines (worktree path, then endpoint id).
# Capture both from ONE call - calling it twice would launch the worker twice.
# On either failure below, no meta record has been written yet, so nothing
# else would ever find/clean up whatever backend_spawn may have already
# created - roll it back here, best-effort, before reporting the failure.
SPAWN_OUTPUT=$(backend_spawn "$ID" "$PROJECT" "$BRIEF" "$BRANCH") || {
  backend_spawn_cleanup "$ID" "$PROJECT" "$BRANCH" 2>/dev/null || true
  fail "backend_spawn failed"
}
WORKTREE=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 1p)
ENDPOINT=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 2p)
[ -n "$WORKTREE" ] && [ -n "$ENDPOINT" ] || {
  backend_spawn_cleanup "$ID" "$PROJECT" "$BRANCH" 2>/dev/null || true
  fail "backend_spawn returned malformed output: $SPAWN_OUTPUT"
}

chief_meta_set "$ID" project "$PROJECT"
chief_meta_set "$ID" mode "$MODE"
chief_meta_set "$ID" branch "$BRANCH"
chief_meta_set "$ID" worktree "$WORKTREE"
chief_meta_set "$ID" endpoint "$ENDPOINT"
chief_meta_set "$ID" status working

"$CHIEF_ROOT/bin/chief-backlog.sh" status "$ID" in-flight 2>/dev/null || true

echo "spawned: $ID ($MODE) in $WORKTREE"
