#!/usr/bin/env bash
# Devcontainer setup, run via postCreateCommand (idempotent).
set -euo pipefail

# The runtime injects HOME=/root into /etc/environment, so SSH logins get the wrong $HOME.
sudo sed -i '/^HOME=/d' /etc/environment
HOME="$(getent passwd "$(id -u)" | cut -d: -f6)"

# Named volumes and the workspace mount's parent come up root-owned.
for dir in "$HOME/.config" "$HOME/.claude" "$HOME/.codex" "$HOME/.copilot" \
  "$HOME/.config/gh" "$HOME/.config/orca" "$HOME/workspaces"; do
  if [ -d "$dir" ] && [ ! -O "$dir" ]; then
    sudo chown "$(id -u):$(id -g)" "$dir"
  fi
done

# sshd ignores workspaceFolder: start SSH logins in the workspace.
workspace_dir="$(cd "$(dirname "$0")/.." && pwd)"
if ! grep -q '# ssh-workspace-cd' "$HOME/.bashrc"; then
  cat >>"$HOME/.bashrc" <<BASHRC

# ssh-workspace-cd
if [ -n "\${SSH_CONNECTION:-}" ] && [ "\$PWD" = "\$HOME" ]; then
  cd "$workspace_dir"
fi
BASHRC
fi

# Key-only SSH: the public key comes from the host's SSH_AUTHORIZED_KEY.
if [ -n "${SSH_AUTHORIZED_KEY:-}" ]; then
  install -d -m 700 "$HOME/.ssh"
  printf '%s\n' "$SSH_AUTHORIZED_KEY" >"$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"
else
  echo "setup: SSH_AUTHORIZED_KEY is not set on the host, SSH login is disabled" >&2
fi

printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' |
  sudo tee /etc/ssh/sshd_config.d/10-key-only.conf >/dev/null
sudo /etc/init.d/ssh reload
