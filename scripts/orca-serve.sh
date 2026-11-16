#!/usr/bin/env bash
# Starts the Orca server on every container start (postStartCommand). Idempotent.
set -euo pipefail

# $HOME can be the stale /root value here; resolve it from /etc/passwd.
HOME="$(getent passwd "$(id -u)" | cut -d: -f6)"

if pgrep -f "orca-ide serve" >/dev/null 2>&1; then
  echo "orca-serve: orca-ide serve already running, skipping"
  exit 0
fi

LOG_DIR="$HOME/.orca"
mkdir -p "$LOG_DIR"

echo "orca-serve: starting orca-ide serve --pairing-address ${ORCA_PAIRING_ADDRESS}"
# setsid detaches into a new session so the server outlives the postStartCommand session.
setsid nohup orca-ide serve --port 6768 --pairing-address "$ORCA_PAIRING_ADDRESS" --json \
  >"$LOG_DIR/serve.log" 2>&1 </dev/null &
disown

echo "orca-serve: started; tail -f $LOG_DIR/serve.log for the pairing URL"
