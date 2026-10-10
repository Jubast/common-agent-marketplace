#!/usr/bin/env bash
# agent.sh - loads the configured agent adapter and nothing else. Sourced
# after paths.sh (needs $CONFIG, $STATE).
#
# Adapter contract - each agents/<name>.sh defines all of:
#   agent_name             -> the agent's native kind (herdr --kind)
#   agent_args             -> CLI args the backends start it with
#   agent_command          -> full command line to start it
#   agent_prepare <dir>... -> before a worker starts: pre-accept its folder trust
#   agent_release <dir>    -> undo agent_prepare for <dir> (teardown, spawn rollback)
#   agent_ready_text       -> screen text (egrep) meaning it is ready for a prompt
#
# Selection: $CHIEF_AGENT env var, else $CONFIG/agent, else "claude".

CHIEF_AGENT="${CHIEF_AGENT:-}"
if [ -z "$CHIEF_AGENT" ] && [ -f "$CONFIG/agent" ]; then
  CHIEF_AGENT=$(tr -d '[:space:]' < "$CONFIG/agent")
fi
CHIEF_AGENT="${CHIEF_AGENT:-claude}"

if [[ ! $CHIEF_AGENT =~ ^[a-z0-9-]+$ ]] || [ ! -f "$CHIEF_ROOT/bin/lib/agents/$CHIEF_AGENT.sh" ]; then
  echo "chief-agent: unsupported agent '$CHIEF_AGENT' (no agents/$CHIEF_AGENT.sh)" >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$CHIEF_ROOT/bin/lib/agents/$CHIEF_AGENT.sh"
