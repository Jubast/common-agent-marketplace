#!/usr/bin/env bash
# chief-backlog.sh - the whole backlog: one markdown file, no external tool.
#
# Format, one record per section in $DATA/backlog.md:
#   ## <id> [<status>] <title>
#   note: <free text, optional>
#
# status is one of: queued | in-flight | held | done
#
# Usage:
#   chief-backlog.sh add <id> "<title>"              -> queued
#   chief-backlog.sh status <id> <status>             -> update status
#   chief-backlog.sh note <id> "<text>"                -> replace the note line
#   chief-backlog.sh hold <id> "<reason>"               -> status=held + note
#   chief-backlog.sh done <id>                           -> status=done
#   chief-backlog.sh list [status]                        -> print matching records
#   chief-backlog.sh next                                  -> first queued id, or nothing
#   chief-backlog.sh show <id>                               -> print one record
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-lock.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"

BACKLOG="$DATA/backlog.md"
LOCK="$STATE/.backlog.lock"
touch "$BACKLOG"

fail() { echo "chief-backlog: $*" >&2; exit 1; }

# Rewrite the whole file from an awk program, under the backlog lock.
# All mutating subcommands funnel through this so no two writers can race.
_rewrite() {
  local awk_program=$1
  shift
  chief_lock_acquire "$LOCK" 10 || fail "could not acquire backlog lock"
  local tmp
  tmp=$(mktemp "$DATA/.backlog.md.XXXXXX")
  # "$@" (the -v assignments) must precede the program text - they're awk
  # options, not operands - so it comes first even though it read the other
  # way at the call sites below.
  if ! awk "$@" "$awk_program" "$BACKLOG" > "$tmp"; then
    rm -f "$tmp"
    chief_lock_release "$LOCK"
    fail "backlog rewrite failed"
  fi
  mv "$tmp" "$BACKLOG"
  chief_lock_release "$LOCK"
}

cmd_add() {
  local id=$1 title=$2
  grep -q "^## $id " "$BACKLOG" 2>/dev/null && fail "task $id already exists in the backlog"
  chief_lock_acquire "$LOCK" 10 || fail "could not acquire backlog lock"
  {
    printf '## %s [queued] %s\n' "$id" "$title"
  } >> "$BACKLOG"
  chief_lock_release "$LOCK"
  echo "added: $id [queued] $title"
}

cmd_status() {
  local id=$1 new=$2
  case "$new" in
    queued|in-flight|held|done) ;;
    *) fail "status must be one of: queued in-flight held done" ;;
  esac
  grep -q "^## $id " "$BACKLOG" || fail "no such task: $id"
  _rewrite '
    BEGIN { FS=OFS=" " }
    $0 ~ "^## " id " \\[" {
      sub(/\[[a-z-]+\]/, "[" new "]")
    }
    { print }
  ' -v id="$id" -v new="$new"
  echo "status: $id -> $new"
}

cmd_note() {
  local id=$1 text=$2
  grep -q "^## $id " "$BACKLOG" || fail "no such task: $id"
  _rewrite '
    $0 ~ "^## " id " \\[" { print; in_record=1; wrote_note=0; next }
    in_record && /^note: / { print "note: " text; wrote_note=1; next }
    in_record && /^## / { if (!wrote_note) print "note: " text; in_record=0 }
    { print }
    END { if (in_record && !wrote_note) print "note: " text }
  ' -v id="$id" -v text="$text"
  echo "note: $id updated"
}

cmd_hold() {
  local id=$1 reason=$2
  cmd_status "$id" held
  cmd_note "$id" "$reason"
  # A held/done backlog item has been acted on by the normal flow - take it
  # out of chief-watch.sh's in_flight_ids so it stops re-notifying about the
  # same already-surfaced terminal state on every subsequent Stop hook.
  chief_meta_exists "$id" && chief_meta_set "$id" status held
  return 0
}

cmd_done() {
  local id=$1
  cmd_status "$id" done
  chief_meta_exists "$id" && chief_meta_set "$id" status done
  return 0
}

cmd_list() {
  local filter=${1:-}
  if [ -n "$filter" ]; then
    grep "^## .* \[$filter\] " "$BACKLOG" || true
  else
    grep "^## " "$BACKLOG" || true
  fi
}

cmd_next() {
  grep "^## .* \[queued\] " "$BACKLOG" | head -1 | sed -E 's/^## ([^ ]+) .*/\1/' || true
}

cmd_show() {
  local id=$1
  awk -v id="$id" '
    $0 ~ "^## " id " \\[" { print; in_record=1; next }
    in_record && /^## / { exit }
    in_record { print }
  ' "$BACKLOG"
}

case "${1:-}" in
  add)    cmd_add "$2" "$3" ;;
  status) cmd_status "$2" "$3" ;;
  note)   cmd_note "$2" "$3" ;;
  hold)   cmd_hold "$2" "$3" ;;
  done)   cmd_done "$2" ;;
  list)   cmd_list "${2:-}" ;;
  next)   cmd_next ;;
  show)   cmd_show "$2" ;;
  *)
    echo "usage: chief-backlog.sh add|status|note|hold|done|list|next|show ..." >&2
    exit 2
    ;;
esac
