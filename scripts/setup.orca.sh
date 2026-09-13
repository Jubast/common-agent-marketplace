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
# stablyai/orca has no marketplace.json, so orca-cli/orchestration must stay on npx.
installed_skills="$(npx --yes skills list -g 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')"
if grep -q '^orca-cli' <<<"$installed_skills" && grep -q '^orchestration' <<<"$installed_skills"; then
  echo "setup: [skills] orca-cli, orchestration already installed, skipping"
else
  echo "setup: [skills] installing orca-cli, orchestration @ v1.4.200"
  npx --yes skills add https://github.com/stablyai/orca/tree/v1.4.200 --skill orca-cli --skill orchestration --agent claude-code --global -y
fi

# `npx skills add` drops plugin hooks silently, so superpowers and this
# repo's plugins are installed natively instead (idempotent on re-run).

# `owner/repo#ref` pins the marketplace to a tag, like the old npx tree URL did.
echo "setup: [plugins] installing superpowers@v6.3.0"
if ! claude plugin marketplace add "obra/superpowers#v6.3.0" --scope user; then
  echo "setup: superpowers marketplace add failed, continuing" >&2
fi
if ! claude plugin install superpowers@superpowers-dev -y --scope user --json; then
  echo "setup: superpowers install failed, continuing" >&2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "setup: [plugins] installing common-agent-marketplace plugins"
if ! claude plugin marketplace add "$REPO_ROOT" --scope user; then
  echo "setup: common-agent-marketplace marketplace add failed, continuing" >&2
fi

# Only these are meant to install globally; the rest are per-project.
for plugin_name in using-orca conventional-commits conventional-pull-requests; do
  if ! claude plugin install "${plugin_name}@common-agent-marketplace" -y --scope user --json; then
    echo "setup: ${plugin_name} install failed, continuing" >&2
  fi
done
