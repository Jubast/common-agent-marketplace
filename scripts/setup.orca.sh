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

# superpowers is pinned to a tag; the other installs float on their default branch.
echo "setup: [skills] installing superpowers@v6.3.0"
npx --yes skills add https://github.com/obra/superpowers/tree/v6.3.0 --skill '*' --agent claude-code --global -y

echo "setup: [skills] installing common-agent-marketplace plugins"
npx --yes skills add https://github.com/Jubast/common-agent-marketplace --skill '*' --agent claude-code --global -y

# `orca skills install` refuses to run over this SSH-forwarded shell, so we call npx directly.
echo "setup: [skills] installing orca-cli, orchestration"
npx --yes skills add https://github.com/stablyai/orca --skill orca-cli --skill orchestration --agent claude-code --global -y

# `npx skills add` only copies SKILL.md/skill folders - it has no concept of
# plugin hooks, so it can't register using-orca's SessionStart hook. Install
# it natively instead so the hook actually gets registered (confirmed via
# enabledPlugins + the plugin cache in an isolated sandbox this session).
# Both commands below are already idempotent on a re-run (exit 0, no error)
# but we still guard them so an unexpected failure here can't hard-fail the
# rest of devcontainer setup.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "setup: [plugins] installing using-orca (native install, needed for its SessionStart hook)"
claude plugin marketplace add "$REPO_ROOT" --scope user \
  || echo "setup: marketplace add failed, continuing" >&2
claude plugin install using-orca@common-agent-marketplace -y --scope user --json \
  || echo "setup: using-orca install failed, continuing" >&2
