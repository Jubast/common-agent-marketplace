#!/usr/bin/env bash
# Generic devcontainer setup, run via postCreateCommand.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_SETUP="$SCRIPT_DIR/setup.local.sh"

if [ -f "$LOCAL_SETUP" ]; then
  echo "setup: running local setup ($LOCAL_SETUP)"
  bash "$LOCAL_SETUP"
fi
