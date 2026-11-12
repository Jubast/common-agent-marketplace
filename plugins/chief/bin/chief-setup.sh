#!/usr/bin/env bash
# chief-setup.sh - one-time CHIEF_HOME setup: pick a backend, verify it's on
# PATH, gitignore runtime state. Safe to re-run (idempotent).
#
# Usage: chief-setup.sh --backend herdr|orca|hc
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/paths.sh"
chief_ensure_dirs

fail() { echo "chief-setup: $*" >&2; exit 1; }

BACKEND=""
while [ $# -gt 0 ]; do
  case "$1" in
    --backend) BACKEND=${2:-}; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
case "$BACKEND" in
  herdr|orca|hc) ;;
  *) fail "usage: chief-setup.sh --backend herdr|orca|hc" ;;
esac

echo "$BACKEND" > "$CONFIG/backend"
echo "backend: $BACKEND -> $CONFIG/backend"

if command -v "$BACKEND" >/dev/null 2>&1; then
  echo "backend check: '$BACKEND' found on PATH"
else
  echo "backend check: WARNING - '$BACKEND' not found on PATH; install (and for Orca, start) it before dispatching"
fi

# Chief's own harness: Codex wakes it through `codex queue`, Copilot through an
# extension that needs experimental on.
if command -v codex >/dev/null 2>&1 && ! codex queue --help >/dev/null 2>&1; then
  echo "harness check: WARNING - this codex has no 'queue' command; Chief on Codex cannot be woken (see README, Harnesses)"
fi
if command -v copilot >/dev/null 2>&1 \
  && ! jq -e '.experimental == true' "${COPILOT_HOME:-$HOME/.copilot}/settings.json" >/dev/null 2>&1; then
  echo "harness check: WARNING - copilot has 'experimental' off; Chief on Copilot needs --experimental (or /settings experimental on) for its wake extension"
fi

GIT_ROOT=$(git -C "$(dirname "$CHIEF_HOME")" rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$GIT_ROOT" ]; then
  GITIGNORE="$GIT_ROOT/.gitignore"
  touch "$GITIGNORE"
  if grep -qxF ".chief/" "$GITIGNORE" 2>/dev/null; then
    echo "gitignore: .chief/ already ignored"
  else
    printf '%s\n' ".chief/" >> "$GITIGNORE"
    echo "gitignore: added .chief/ to $GITIGNORE"
  fi
else
  echo "gitignore: no git repo found here, skipped"
fi

echo "done: Chief is configured at this CHIEF_HOME"
