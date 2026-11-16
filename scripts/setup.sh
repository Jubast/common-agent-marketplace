#!/usr/bin/env bash
# Devcontainer setup, run via postCreateCommand. Idempotent.
set -euo pipefail

# The container runtime injects a stray HOME="/root" into /etc/environment,
# which gives SSH logins the wrong $HOME.
if grep -q '^HOME=' /etc/environment 2>/dev/null; then
  echo "setup: removing stray HOME override from /etc/environment"
  sudo sed -i '/^HOME=/d' /etc/environment
fi

# This script's own $HOME may still be the stale value; resolve it from /etc/passwd.
HOME="$(getent passwd "$(id -u)" | cut -d: -f6)"

# Named volumes, and the parents Docker creates for them, come up root-owned.
ROOT_OWNED_VOLUME_DIRS=(
  "$HOME/.config"
  "$HOME/.claude"
  "$HOME/.codex"
  "$HOME/.copilot"
  "$HOME/.config/gh"
  "$HOME/.config/orca"
  "$HOME/.history"
  "$HOME/workspaces"
)

for dir in "${ROOT_OWNED_VOLUME_DIRS[@]}"; do
  if [ -d "$dir" ] && [ ! -O "$dir" ]; then
    echo "setup: fixing ownership of $dir"
    sudo chown "$(id -u):$(id -g)" "$dir"
  fi
done

# sshd ignores workspaceFolder, so SSH logins start in $HOME; cd into the workspace instead.
workspace_dir="$(cd "$(dirname "$0")/.." && pwd)"
if ! grep -q '# ssh-workspace-cd' "$HOME/.bashrc" 2>/dev/null; then
  echo "setup: making SSH logins start in $workspace_dir"
  cat >>"$HOME/.bashrc" <<BASHRC

# ssh-workspace-cd
if [ -n "\${SSH_CONNECTION:-}" ] && [ "\$PWD" = "\$HOME" ]; then
  cd "$workspace_dir"
fi
BASHRC
fi

# SSH login is by public key only; the key is the gitignored .devcontainer/authorized_keys.
authorized_keys="$workspace_dir/.devcontainer/authorized_keys"
if [ -f "$authorized_keys" ]; then
  echo "setup: installing the authorized SSH key"
  install -d -m 700 "$HOME/.ssh"
  install -m 600 "$authorized_keys" "$HOME/.ssh/authorized_keys"
else
  echo "setup: .devcontainer/authorized_keys not found, SSH login is disabled" >&2
fi

echo "setup: disabling SSH password login"
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' |
  sudo tee /etc/ssh/sshd_config.d/10-key-only.conf >/dev/null
sudo /etc/init.d/ssh reload
