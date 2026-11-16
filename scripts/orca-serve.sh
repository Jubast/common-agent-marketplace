#!/usr/bin/env bash
# Starts the Orca server on every container start (postStartCommand).
set -euo pipefail

HOME="$(getent passwd "$(id -u)" | cut -d: -f6)"

if pgrep -f "orca-ide serve" >/dev/null; then
  echo "orca-serve: already running"
  exit 0
fi

mkdir -p "$HOME/.orca"
# setsid: survive the end of the postStartCommand session.
setsid nohup orca-ide serve --port 6768 --pairing-address "$ORCA_PAIRING_ADDRESS" --json \
  >"$HOME/.orca/serve.log" 2>&1 </dev/null &
echo "orca-serve: started; pairing URL in $HOME/.orca/serve.log"
