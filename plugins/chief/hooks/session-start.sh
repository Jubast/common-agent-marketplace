#!/usr/bin/env bash
# session-start.sh - force-injects the using-chief identity skill as
# additionalContext, plus a backlog/in-flight digest when one exists. Stands
# down entirely inside a spawned builder's own worktree/session - see
# bin/lib/chief-worktree.sh for why that check is race-free.
set -euo pipefail

CHIEF_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../bin/lib/chief-worktree.sh
. "$CHIEF_PLUGIN_ROOT/bin/lib/chief-worktree.sh"

if chief_is_linked_worktree; then
  echo '{}'
  exit 0
fi

CHIEF_HOME="${CHIEF_HOME:-}"
if [ -z "$CHIEF_HOME" ]; then
  _git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  CHIEF_HOME="${_git_root:-$(pwd)}/.chief"
fi

SKILL_FILE="$CHIEF_PLUGIN_ROOT/skills/using-chief/SKILL.md"
[ -f "$SKILL_FILE" ] || { echo '{}'; exit 0; }

STATE="$CHIEF_HOME/state"
BACKLOG="$CHIEF_HOME/data/backlog.md"
BACKEND_CONFIG="$CHIEF_HOME/config/backend"

digest="## Configuration"$'\n'
if [ -f "$BACKEND_CONFIG" ]; then
  digest+="backend: $(cat "$BACKEND_CONFIG") (from .chief/config/backend)"$'\n'
else
  digest+="NOT CONFIGURED YET at CHIEF_HOME ($CHIEF_HOME) - load the 'setup' skill once here before dispatching anything. This is a one-time step for this CHIEF_HOME, not something to repeat inside each project you dispatch into."$'\n'
fi

digest+=$'\n'"## Backlog and in-flight tasks"$'\n'

if [ -d "$STATE" ]; then
  if [ -f "$BACKLOG" ] && [ -s "$BACKLOG" ]; then
    digest+=$'\n'"### Backlog"$'\n'"$(grep '^## ' "$BACKLOG" || true)"$'\n'
  else
    digest+=$'\n'"### Backlog"$'\n'"(empty)"$'\n'
  fi
  digest+=$'\n'"### In-flight"$'\n'
  any=0
  for f in "$STATE"/*.meta; do
    [ -e "$f" ] || continue
    id=$(basename "$f" .meta)
    status=$(grep '^status=' "$f" | cut -d= -f2- || echo unknown)
    [ "$status" = "working" ] || continue
    any=1
    line=$(tail -n 1 "$STATE/$id.status" 2>/dev/null || echo "no status yet")
    mode=$(grep '^mode=' "$f" | cut -d= -f2- || echo unknown)
    digest+="- $id: $line [mode: $mode]"$'\n'
  done
  [ "$any" -eq 0 ] && digest+="(none)"$'\n'
else
  digest+=$'\n'"(.chief/ not created yet at CHIEF_HOME - it will be on first use)"$'\n'
fi

escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

combined="$(cat "$SKILL_FILE")"$'\n\n'"$digest"
escaped=$(escape_for_json "<EXTREMELY_IMPORTANT>
You MUST follow the 'using-chief' identity and job description below. It applies to this Chief session's CHIEF_HOME (typically your top-level workspace root) - a single shared home, not something to set up separately inside each project you dispatch into:

$combined
</EXTREMELY_IMPORTANT>")
printf '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "%s"}}\n' "$escaped"
