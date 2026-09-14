#!/usr/bin/env bash
# Injects using-conventional-changes's SKILL.md as additionalContext at every session start.
set -euo pipefail

SKILL_FILE="${CLAUDE_PLUGIN_ROOT}/skills/using-conventional-changes/SKILL.md"
[ -f "$SKILL_FILE" ] || { echo '{}'; exit 0; }

# Single-pass bash substitutions - no python3/jq dependency, same approach as
# obra/superpowers's session-start hook.
escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

escaped=$(escape_for_json "$(cat "$SKILL_FILE")")
session_context="<EXTREMELY_IMPORTANT>\nYou MUST follow the 'using-conventional-changes' skill below:\n\n${escaped}\n</EXTREMELY_IMPORTANT>"
printf '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "%s"}}\n' "$session_context"
