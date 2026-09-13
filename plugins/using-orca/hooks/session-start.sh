#!/usr/bin/env bash
# SessionStart hook for the using-orca plugin: only inject guidance when
# Orca is actually running (never nag with stale advice), and always exit 0
# so a broken hook can never fail session start.
set -euo pipefail

if ! command -v orca >/dev/null 2>&1 || ! timeout 3 orca status --json >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

SKILL_FILE="${CLAUDE_PLUGIN_ROOT}/skills/using-orca/SKILL.md"

if [ ! -f "$SKILL_FILE" ]; then
  echo '{}'
  exit 0
fi

GUIDANCE=$(cat "$SKILL_FILE")

if command -v python3 >/dev/null 2>&1; then
  ESCAPED=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<< "$GUIDANCE")
elif command -v jq >/dev/null 2>&1; then
  ESCAPED=$(jq -Rs . <<< "$GUIDANCE")
else
  # Last-resort manual JSON string escaping via bash parameter expansion
  # (order matters: backslashes first, then quotes, then join lines with \n).
  ESCAPED='"'
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line//\\/\\\\}
    line=${line//\"/\\\"}
    ESCAPED+="${line}\\n"
  done <<< "$GUIDANCE"
  ESCAPED="${ESCAPED%\\n}\""
fi

printf '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": %s}}\n' "$ESCAPED"
