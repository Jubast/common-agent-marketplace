#!/usr/bin/env bash
# Injects using-orca's SKILL.md as additionalContext, only when Orca is running.
set -euo pipefail

if ! command -v orca >/dev/null 2>&1 || ! timeout 3 orca status --json >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

SKILL_FILE="${CLAUDE_PLUGIN_ROOT}/skills/using-orca/SKILL.md"
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
session_context="<EXTREMELY_IMPORTANT>\nOrca is running. You MUST follow the 'using-orca' skill below:\n\n${escaped}\n</EXTREMELY_IMPORTANT>"
printf '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "%s"}}\n' "$session_context"
