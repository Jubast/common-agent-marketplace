#!/usr/bin/env bash
# Devcontainer setup entrypoint, run via postCreateCommand from every
# devcontainer config under .devcontainer/. Delegates to
# setup.${DEVCONTAINER_ENVIRONMENT}.sh when a config sets that env var via
# containerEnv and a matching script exists
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -n "${DEVCONTAINER_ENVIRONMENT:-}" ]; then
  ENV_SETUP="$SCRIPT_DIR/setup.${DEVCONTAINER_ENVIRONMENT}.sh"
  if [ -f "$ENV_SETUP" ]; then
    echo "setup: running ${DEVCONTAINER_ENVIRONMENT} setup ($ENV_SETUP)"
    bash "$ENV_SETUP"
  else
    echo "setup: DEVCONTAINER_ENVIRONMENT=${DEVCONTAINER_ENVIRONMENT} but $ENV_SETUP not found, skipping" >&2
  fi
fi
