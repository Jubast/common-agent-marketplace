#!/usr/bin/env bash
# claude.sh - Claude Code agent adapter (contract in agent.sh).
# Pre-trust sets hasTrustDialogAccepted in ${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json
# for the exact worktree (claude does not inherit trust from a parent dir).
# Dirs Chief trusted are listed in $STATE/trust-owned; user-trusted ones are
# never touched. Edits are serialized with a lock. Best-effort: failures warn
# and the worker may stall at the trust dialog. CHIEF_NO_PRETRUST=1 disables.

. "$CHIEF_ROOT/bin/lib/lock.sh"

agent_name() { echo claude; }
agent_command() { echo "claude --dangerously-skip-permissions${CHIEF_AGENT_MODEL:+ --model $CHIEF_AGENT_MODEL}${CHIEF_AGENT_ARGS:+ $CHIEF_AGENT_ARGS}"; }
agent_ready_text() { echo 'bypass permissions'; }
agent_paste_text() { echo '\[Pasted text'; }
agent_trust_text() { echo 'trust this folder'; }
agent_trust_keys() { echo 'down enter'; }
agent_input_marker() { echo '❯'; }

_claude_json() { readlink -f "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"; }

# _claude_locked <cmd>... - runs <cmd> holding the trust lock
_claude_locked() {
  local rc
  chief_lock_acquire "$STATE/.trust.lock" 30 || { echo "chief-agent: trust lock busy" >&2; return 1; }
  "$@"; rc=$?
  chief_lock_release "$STATE/.trust.lock"
  return $rc
}

# _claude_edit <dir> <jq-filter> - atomic edit of .claude.json
_claude_edit() {
  local f tmp; f=$(_claude_json)
  [ -f "$f" ] || echo '{}' > "$f"
  tmp=$(mktemp "$f.XXXXXX") && jq --arg p "$1" "$2" "$f" > "$tmp" && mv "$tmp" "$f" \
    || { rm -f "$tmp"; echo "chief-agent: could not update $f" >&2; return 1; }
}

# _claude_dirs <dir> - the dir, plus its symlink-resolved spelling if different
_claude_dirs() { printf '%s\n' "$1"; [ "$(realpath -m "$1")" = "$1" ] || realpath -m "$1"; }

_claude_trust() {  # <dir>
  local d
  while read -r d; do
    jq -e --arg p "$d" '.projects[$p].hasTrustDialogAccepted == true' "$(_claude_json)" >/dev/null 2>&1 && continue
    _claude_edit "$d" '.projects[$p].hasTrustDialogAccepted = true' && echo "$d" >> "$STATE/trust-owned"
  done < <(_claude_dirs "$1")
}

_claude_untrust() {  # <dir>
  local d
  while read -r d; do
    grep -qxF -- "$d" "$STATE/trust-owned" 2>/dev/null || continue
    _claude_edit "$d" 'del(.projects[$p].hasTrustDialogAccepted) | if .projects[$p] == {} then del(.projects[$p]) else . end' || continue
    { grep -vxF -- "$d" "$STATE/trust-owned" || true; } > "$STATE/trust-owned.tmp"
    mv "$STATE/trust-owned.tmp" "$STATE/trust-owned"
  done < <(_claude_dirs "$1")
}

agent_prepare() {  # <dir>
  if [ "${CHIEF_NO_PRETRUST:-}" = 1 ]; then
    echo "chief-agent: CHIEF_NO_PRETRUST=1, folders are not pre-trusted; workers will stall at the trust dialog unless trusted another way" >&2
    return 0
  fi
  _claude_locked _claude_trust "$1" || echo "chief-agent: could not pre-trust $1; the worker may stall at the trust dialog" >&2
  return 0
}

agent_release() {  # <dir> - undo agent_prepare
  [ "${CHIEF_NO_PRETRUST:-}" = 1 ] && return 0
  _claude_locked _claude_untrust "$1" || true
}
