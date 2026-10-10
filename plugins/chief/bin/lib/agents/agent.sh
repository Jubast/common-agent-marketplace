#!/usr/bin/env bash
# agent.sh - loads a task's agent adapter. Sourced after paths.sh and meta.sh.
#
# Adapter contract - each agents/<name>.sh defines all of (the model, if any,
# is in $CHIEF_AGENT_MODEL):
#   agent_name             -> the agent's native kind (herdr --kind)
#   agent_args             -> CLI args the backends start it with
#   agent_command          -> full command line to start it
#   agent_require          -> fails (with a message) unless the agent's CLI is installed
#   agent_prepare <dir>... -> before a worker starts: pre-accept its folder trust
#   agent_release <dir>    -> undo agent_prepare for <dir> (teardown, spawn rollback)
#   agent_ready_text       -> screen text (egrep) meaning it is ready for a prompt
#   agent_paste_text       -> screen text (egrep) it shows for a long pasted prompt
#   agent_input_marker     -> the glyph (egrep) its input line starts with
# and optionally:
#   agent_models           -> the model names it accepts, one per line; when
#                             defined, any other model fails the spawn
#
# The agent, model and command come from the task's meta (chief-spawn.sh
# records them); a task without them runs claude.

# chief_agent_list -> the available adapter names, one per line
chief_agent_list() {
  local f n
  for f in "$CHIEF_ROOT"/bin/lib/agents/*.sh; do
    n=$(basename "$f" .sh)
    case "$n" in agent|select) ;; *) echo "$n" ;; esac
  done
}

# chief_agent_load <agent> - sources the adapter
chief_agent_load() {
  case "$1" in agent|select) set -- "" ;; esac
  if [[ ! $1 =~ ^[a-z0-9-]+$ ]] || [ ! -f "$CHIEF_ROOT/bin/lib/agents/$1.sh" ]; then
    echo "chief-agent: unknown agent '$1' (available: $(chief_agent_list | paste -sd' ' -))" >&2
    return 1
  fi
  unset -f agent_models
  # shellcheck source=/dev/null
  . "$CHIEF_ROOT/bin/lib/agents/$1.sh"
}

# chief_agent_use <id> - loads the adapter recorded in the task's meta
chief_agent_use() {
  local agent
  agent=$(chief_meta_get "$1" agent 2>/dev/null) || agent=""
  CHIEF_AGENT_MODEL=$(chief_meta_get "$1" model 2>/dev/null) || CHIEF_AGENT_MODEL=""
  CHIEF_AGENT_COMMAND=$(chief_meta_get "$1" command 2>/dev/null) || CHIEF_AGENT_COMMAND=""
  chief_agent_load "${agent:-claude}" || return 1
  [ -z "$CHIEF_AGENT_COMMAND" ] && return 0
  # A command override replaces the launch command; herdr starts the agent's
  # own executable, so it takes just the override's arguments.
  agent_command() { echo "$CHIEF_AGENT_COMMAND"; }
  agent_args() { [[ $CHIEF_AGENT_COMMAND != *' '* ]] || echo "${CHIEF_AGENT_COMMAND#* }"; }
}
