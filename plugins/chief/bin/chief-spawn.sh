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

# Bash pattern substitution, not sed - a --spec/--intent value can contain
# literal newlines or sed-delimiter characters, which would break a sed `s`
# expression. Bash's ${var//pattern/replacement} takes the placeholder and
# replacement as plain strings (no per-line processing), but it still treats
# a literal `&` in the replacement as "insert the matched text" and `\` as
# an escape lead-in, so both must be escaped first.
brief_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//&/\\&}
  printf '%s' "$value"
}

BRIEF_CONTENT=$(cat "$TEMPLATE")
BRIEF_CONTENT=${BRIEF_CONTENT//\{TASK\}/$(brief_escape "$INTENT")}
BRIEF_CONTENT=${BRIEF_CONTENT//\{SPEC\}/$(brief_escape "$SPEC")}
BRIEF_CONTENT=${BRIEF_CONTENT//\{BRANCH\}/$(brief_escape "$BRANCH")}
BRIEF_CONTENT=${BRIEF_CONTENT//\{STATUS_FILE\}/$(brief_escape "$STATUS_FILE")}
BRIEF_CONTENT=${BRIEF_CONTENT//\{INBOX_DIR\}/$(brief_escape "$INBOX_DIR")}
BRIEF_CONTENT=${BRIEF_CONTENT//\{REPORT_FILE\}/$(brief_escape "$REPORT_FILE")}
printf '%s\n' "$BRIEF_CONTENT" > "$BRIEF"

# backend_spawn prints exactly two lines (worktree path, then endpoint id).
# Capture both from ONE call - calling it twice would launch the worker twice.
SPAWN_OUTPUT=$(backend_spawn "$ID" "$PROJECT" "$BRIEF" "$BRANCH") || fail "backend_spawn failed"
WORKTREE=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 1p)
ENDPOINT=$(printf '%s\n' "$SPAWN_OUTPUT" | sed -n 2p)
[ -n "$WORKTREE" ] && [ -n "$ENDPOINT" ] || fail "backend_spawn returned malformed output: $SPAWN_OUTPUT"

chief_meta_set "$ID" project "$PROJECT"
chief_meta_set "$ID" mode "$MODE"
chief_meta_set "$ID" branch "$BRANCH"
chief_meta_set "$ID" worktree "$WORKTREE"
chief_meta_set "$ID" endpoint "$ENDPOINT"
chief_meta_set "$ID" status working

"$CHIEF_ROOT/bin/chief-backlog.sh" status "$ID" in-flight 2>/dev/null || true

echo "spawned: $ID ($MODE) in $WORKTREE"
