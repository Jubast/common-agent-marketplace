#!/usr/bin/env bash
# Orca-devcontainer-only setup, run by scripts/setup.sh when
# DEVCONTAINER_ENVIRONMENT=orca (see .devcontainer/orca/devcontainer.json).
# Everything here only applies under that config's sshd feature and named
# volume mounts, and its claude-code feature - none of which the public
# devcontainer installs.
set -euo pipefail

# The container runtime injects a stray HOME="/root" into /etc/environment
# at container start (it's not baked into any built image layer) and applies
# it to every SSH session's default per-user HOME from /etc/passwd - so any
# SSH login (not just as root) ends up with $HOME=/root, breaking anything
# that reads dotfiles or caches there.
if grep -q '^HOME=' /etc/environment 2>/dev/null; then
  echo "setup: removing stray HOME override from /etc/environment (breaks \$HOME for SSH logins)"
  sudo sed -i '/^HOME=/d' /etc/environment
fi

# Named volumes mounted at these paths (see .devcontainer/orca/devcontainer.json) come up root-owned.
ROOT_OWNED_VOLUME_DIRS=(
  "$HOME/.claude"
  "$HOME/.config/gh"
  "$HOME/.history"
  "$HOME/workspaces"
)

for dir in "${ROOT_OWNED_VOLUME_DIRS[@]}"; do
  if [ -d "$dir" ] && [ ! -O "$dir" ]; then
    echo "setup: fixing ownership of $dir"
    sudo chown "$(id -u):$(id -g)" "$dir"
  fi
done

if ! command -v claude >/dev/null 2>&1; then
  echo "setup: claude CLI not found on PATH, skipping" >&2
  exit 0
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "setup: npx not found, skipping skill installs" >&2
  exit 0
fi

# `orca skills install` refuses to run over this SSH-forwarded shell, so we call npx directly.
# stablyai/orca has no .claude-plugin/marketplace.json of its own, so
# orca-cli/orchestration have no native install path and must stay on npx.
echo "setup: [skills] installing orca-cli, orchestration"
npx --yes skills add https://github.com/stablyai/orca --skill orca-cli --skill orchestration --agent claude-code --global -y

# `npx skills add` only copies SKILL.md/skill folders - it has no concept of
# plugin hooks, so it silently drops any hooks/hooks.json a plugin ships
# (confirmed for both superpowers's own SessionStart hook and this repo's
# using-orca plugin). Install both marketplaces natively instead
# (`claude plugin marketplace add` + `claude plugin install`) so hooks
# actually get registered - confirmed end-to-end in an isolated sandbox this
# session (enabledPlugins + cached hooks.json + preserved exec bit, for both
# superpowers and every plugin in this repo). Both commands are naturally
# idempotent on a re-run (exit 0, no error) but we still guard them so an
# unexpected failure here can't hard-fail the rest of devcontainer setup.

# `owner/repo#ref` pins the marketplace clone to a specific tag/branch/SHA,
# the same way the old npx `.../tree/v6.3.0` URL did.
echo "setup: [plugins] installing superpowers@v6.3.0"
claude plugin marketplace add "obra/superpowers#v6.3.0" --scope user \
  || echo "setup: superpowers marketplace add failed, continuing" >&2
claude plugin install superpowers@superpowers-dev -y --scope user --json \
  || echo "setup: superpowers install failed, continuing" >&2

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
echo "setup: [plugins] installing common-agent-marketplace plugins"
claude plugin marketplace add "$REPO_ROOT" --scope user \
  || echo "setup: common-agent-marketplace marketplace add failed, continuing" >&2

# Installs every plugin listed in marketplace.json (not just using-orca) so
# this stays in sync as plugins are added, without hardcoding names here.
if command -v python3 >/dev/null 2>&1; then
  while IFS= read -r plugin_name; do
    claude plugin install "${plugin_name}@common-agent-marketplace" -y --scope user --json \
      || echo "setup: ${plugin_name} install failed, continuing" >&2
  done < <(python3 -c "import json, sys; print('\n'.join(p['name'] for p in json.load(open(sys.argv[1]))['plugins']))" "$MARKETPLACE_JSON")
else
  echo "setup: python3 not found, skipping native installs of common-agent-marketplace plugins" >&2
fi
