#!/usr/bin/env bash
# agent.sh - loads a task's agent adapter and selects a new task's agent
# profile. Sourced after paths.sh and meta.sh.
#
# Adapter contract - each agents/<name>.sh defines all of (the model and
# extra args, if any, are in $CHIEF_AGENT_MODEL / $CHIEF_AGENT_ARGS):
#   agent_name             -> the agent's native kind (herdr --kind)
#   agent_args             -> CLI args the backends start it with
#   agent_command          -> full command line to start it
#   agent_require          -> fails (with a message) unless the agent's CLI is installed
#   agent_prepare <dir>    -> before a worker starts: pre-accept its folder trust
#   agent_release <dir>    -> undo agent_prepare for <dir> (teardown, spawn rollback)
#   agent_ready_text       -> screen text (egrep) meaning it is ready for a prompt
#   agent_paste_text       -> screen text (egrep) it shows for a long pasted prompt
#   agent_input_marker     -> the glyph (egrep) its input line starts with
# and optionally:
#   agent_models           -> the model names it accepts, one per line; when
#                             defined, any other model fails the spawn
#
# A task's agent, model, args and command come from its meta (chief-spawn.sh
# records them); a task without them runs claude.

. "$CHIEF_ROOT/bin/lib/lock.sh"

# --- loading ---------------------------------------------------------------

chief_agent_list() {  # the available adapter names, one per line
  local f
  for f in "$CHIEF_ROOT"/bin/lib/agents/*.sh; do basename "$f" .sh; done | grep -vx agent
}

chief_agent_load() {  # <agent> - sources the adapter
  if [[ ! $1 =~ ^[a-z0-9-]+$ ]] || [ ! -f "$CHIEF_ROOT/bin/lib/agents/$1.sh" ] || [ "$1" = agent ]; then
    echo "chief-agent: unknown agent '$1' (available: $(chief_agent_list | paste -sd' ' -))" >&2
    return 1
  fi
  unset -f agent_models
  # shellcheck source=/dev/null
  . "$CHIEF_ROOT/bin/lib/agents/$1.sh"
}

chief_agent_use() {  # <id> - loads the adapter recorded in the task's meta
  local agent
  agent=$(chief_meta_get "$1" agent 2>/dev/null) || agent=""
  CHIEF_AGENT_MODEL=$(chief_meta_get "$1" model 2>/dev/null) || CHIEF_AGENT_MODEL=""
  CHIEF_AGENT_ARGS=$(chief_meta_get "$1" args 2>/dev/null) || CHIEF_AGENT_ARGS=""
  CHIEF_AGENT_COMMAND=$(chief_meta_get "$1" command 2>/dev/null) || CHIEF_AGENT_COMMAND=""
  chief_agent_load "${agent:-claude}" || return 1
  if [ -n "$CHIEF_AGENT_ARGS" ]; then
    # Appended to the adapter's own args (the unattended and model flags stay).
    CHIEF_AGENT_BASE_ARGS=$(agent_args)
    agent_args() { echo "$CHIEF_AGENT_BASE_ARGS $CHIEF_AGENT_ARGS"; }
  fi
  if [ -n "$CHIEF_AGENT_COMMAND" ]; then
    # Replaces the launch command; herdr starts the agent's own executable,
    # so it takes just the override's arguments.
    agent_command() { echo "$CHIEF_AGENT_COMMAND"; }
    agent_args() { [[ $CHIEF_AGENT_COMMAND != *' '* ]] || echo "${CHIEF_AGENT_COMMAND#* }"; }
  fi
}

# --- selection -------------------------------------------------------------
#
# .chief/config/agents (no file: claude):
#   strategy = first | round-robin | random | weighted        (default first)
#   <agent>[:<model>] [weight=N] [args="<extra CLI args>"] [command="<launch command>"]
#   [builder] / [scout]   a pool (and strategy) for that kind of worker only;
#                         each falls back to the global one. '#' starts a comment.
#
# chief_agent_select <mode> sets SEL_AGENT, SEL_MODEL, SEL_ARGS, SEL_COMMAND
# (mode ship is the builder). weighted and random draw from $CHIEF_AGENT_RANDOM
# when it is set (a test hook), else from $RANDOM; random ignores weights.

SEP=$'\x1f'

chief_agent_profile() {  # <agent[:model]> - validates, sets P_AGENT and P_MODEL
  local re='^([a-z0-9-]+)(:([A-Za-z0-9._/@:+-]+))?$'
  [[ $1 =~ $re ]] || { echo "chief-agent: bad profile '$1' (want <agent>[:<model>])" >&2; return 1; }
  P_AGENT=${BASH_REMATCH[1]} P_MODEL=${BASH_REMATCH[3]:-}
}

# _chief_agent_entry <line> - prints "agent SEP model SEP weight SEP command SEP args"
_chief_agent_entry() {
  local rest=$1 weight=1 cmd="" args="" profile
  local opt='^[[:space:]]+(weight=([0-9]+)|command="([^"]*)"|args="([^"]*)")(.*)$'
  read -r profile rest <<< "$rest"
  chief_agent_profile "$profile" || return 1
  rest=" $rest"
  while [[ $rest =~ $opt ]]; do
    weight=${BASH_REMATCH[2]:-$weight} cmd=${BASH_REMATCH[3]:-$cmd} args=${BASH_REMATCH[4]:-$args}
    rest=${BASH_REMATCH[5]}
  done
  [[ $rest =~ ^[[:space:]]*(#.*)?$ ]] || { echo "chief-agent: unexpected '$rest' after '$profile'" >&2; return 1; }
  printf '%s\n' "$P_AGENT$SEP$P_MODEL$SEP$weight$SEP$cmd$SEP$args"
}

# _chief_agent_read <builder|scout> - sets STRATEGY and POOL (one entry per
# line) from the section's lines, else the global ones
_chief_agent_read() {
  local want=$1 file="$CONFIG/agents" line entry section="" n=0
  local gstrategy="" sstrategy="" gpool="" spool=""
  STRATEGY=first POOL=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    read -r line <<< "$line"  # trim
    case "$line" in
      ""|"#"*) continue ;;
      "["*)
        read -r entry <<< "${line%%#*}"
        case "$entry" in
          "[builder]"|"[scout]") section=${entry//[][]/} ;;
          *) echo "chief-agent: $file:$n: unknown section $entry (builder or scout)" >&2; return 1 ;;
        esac ;;
      strategy*=*)
        read -r entry <<< "${line#*=}"
        entry=${entry%%#*}; read -r entry <<< "$entry"
        case "$entry" in
          first|round-robin|random|weighted) ;;
          *) echo "chief-agent: $file:$n: unknown strategy '$entry'" >&2; return 1 ;;
        esac
        if [ -z "$section" ]; then gstrategy=$entry; elif [ "$section" = "$want" ]; then sstrategy=$entry; fi ;;
      *)
        entry=$(_chief_agent_entry "$line") || { echo "chief-agent: $file:$n: $line" >&2; return 1; }
        if [ -z "$section" ]; then gpool+="$entry"$'\n'; elif [ "$section" = "$want" ]; then spool+="$entry"$'\n'; fi ;;
    esac
  done < "$file"
  STRATEGY=${sstrategy:-${gstrategy:-first}}
  POOL=${spool:-$gpool}
  POOL=${POOL%$'\n'}
}

chief_agent_select() {  # <mode>
  local section=${1/ship/builder} cursor rec w i expanded=""
  SEL_AGENT=claude SEL_MODEL="" SEL_ARGS="" SEL_COMMAND=""
  _chief_agent_read "$section" || return 1
  [ -n "$POOL" ] || return 0
  case "$STRATEGY" in
    first) rec=$(head -n 1 <<< "$POOL") ;;
    round-robin)
      chief_lock_acquire "$STATE/.agent-select.lock" 10 || { echo "chief-agent: selection lock busy" >&2; return 1; }
      cursor=$(cat "$STATE/agent-cursor-$section" 2>/dev/null || true)
      [[ $cursor =~ ^[0-9]+$ ]] || cursor=0
      echo $((cursor + 1)) > "$STATE/agent-cursor-$section"
      chief_lock_release "$STATE/.agent-select.lock"
      rec=$(sed -n "$((cursor % $(wc -l <<< "$POOL") + 1))p" <<< "$POOL") ;;
    *)  # weighted or random: draw from the pool with each entry repeated by its weight
      while IFS= read -r rec; do
        IFS=$SEP read -r _ _ w _ <<< "$rec"
        if [ "$STRATEGY" = random ]; then w=1; fi
        for ((i = 0; i < w; i++)); do expanded+="$rec"$'\n'; done
      done <<< "$POOL"
      expanded=${expanded%$'\n'}
      [ -n "$expanded" ] || { echo "chief-agent: every weight is 0" >&2; return 1; }
      rec=$(sed -n "$(( ${CHIEF_AGENT_RANDOM:-$((RANDOM * 32768 + RANDOM))} % $(wc -l <<< "$expanded") + 1 ))p" <<< "$expanded") ;;
  esac
  IFS=$SEP read -r SEL_AGENT SEL_MODEL _ SEL_COMMAND SEL_ARGS <<< "$rec"
}
