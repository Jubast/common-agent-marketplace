#!/usr/bin/env bash
# select.sh - picks a new task's agent profile from $CONFIG/agents. Sourced
# after paths.sh.
#
#   strategy = first | round-robin | random | weighted    (default: first)
#   <agent>[:<model>] [weight=N] [command="<launch command>"]
#   [ship] / [scout]    a pool (and strategy) for that mode only; it falls
#                       back to the global ones. '#' starts a comment.
#
# chief_agent_select <mode> sets SEL_AGENT, SEL_MODEL, SEL_COMMAND. No pool
# means claude. weighted and random draw from $CHIEF_AGENT_RANDOM when it is
# set (a test hook), else from $RANDOM; random ignores weights.

. "$CHIEF_ROOT/bin/lib/lock.sh"

_SEP=$'\x1f'

# chief_agent_profile <agent[:model]> - validates, sets P_AGENT and P_MODEL
chief_agent_profile() {
  local re='^([a-z0-9-]+)(:([A-Za-z0-9._/@:+-]+))?$'
  [[ $1 =~ $re ]] || { echo "chief-agent: bad profile '$1' (want <agent>[:<model>])" >&2; return 1; }
  P_AGENT=${BASH_REMATCH[1]} P_MODEL=${BASH_REMATCH[3]:-}
}

# _chief_agents_entry <line> - prints "agent SEP model SEP weight SEP command"
_chief_agents_entry() {
  local rest=$1 profile weight=1 cmd=""
  local head='^[[:space:]]*([^[:space:]#]+)(.*)$'
  local opt='^[[:space:]]+(weight=([0-9]+)|command="([^"]*)")(.*)$'
  [[ $rest =~ $head ]] || return 1
  profile=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]}
  chief_agent_profile "$profile" || return 1
  while [[ $rest =~ $opt ]]; do
    if [ -n "${BASH_REMATCH[2]}" ]; then weight=${BASH_REMATCH[2]}; fi
    if [ -n "${BASH_REMATCH[3]}" ]; then cmd=${BASH_REMATCH[3]}; fi
    rest=${BASH_REMATCH[4]}
  done
  [[ $rest =~ ^[[:space:]]*(#.*)?$ ]] || { echo "chief-agent: unexpected '$rest' after '$profile'" >&2; return 1; }
  printf '%s\n' "$P_AGENT$_SEP$P_MODEL$_SEP$weight$_SEP$cmd"
}

# _chief_agents_read <mode> - sets STRATEGY and POOL (one entry per line)
_chief_agents_read() {
  local mode=$1 file="$CONFIG/agents" line entry section="" n=0
  local gstrat="" sstrat="" gpool="" spool=""
  local re_section='^[[:space:]]*\[([a-z]+)\][[:space:]]*(#.*)?$'
  local re_strategy='^[[:space:]]*strategy[[:space:]]*=[[:space:]]*([a-z-]+)[[:space:]]*(#.*)?$'
  STRATEGY=first POOL=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue
    if [[ $line =~ $re_section ]]; then
      section=${BASH_REMATCH[1]}
      case "$section" in ship|scout) ;; *) echo "chief-agent: $file:$n: unknown section [$section]" >&2; return 1 ;; esac
    elif [[ $line =~ $re_strategy ]]; then
      case "${BASH_REMATCH[1]}" in
        first|round-robin|random|weighted) ;;
        *) echo "chief-agent: $file:$n: unknown strategy '${BASH_REMATCH[1]}'" >&2; return 1 ;;
      esac
      if [ -z "$section" ]; then gstrat=${BASH_REMATCH[1]}
      elif [ "$section" = "$mode" ]; then sstrat=${BASH_REMATCH[1]}; fi
    else
      entry=$(_chief_agents_entry "$line") || { echo "chief-agent: $file:$n: $line" >&2; return 1; }
      if [ -z "$section" ]; then gpool+="$entry"$'\n'
      elif [ "$section" = "$mode" ]; then spool+="$entry"$'\n'; fi
    fi
  done < "$file"
  STRATEGY=${sstrat:-${gstrat:-first}}
  POOL=${spool:-$gpool}
}

# _chief_agents_weights - the pool's weights, one per line
_chief_agents_weights() {
  local w
  while IFS=$_SEP read -r _ _ w _; do
    if [ "$STRATEGY" = random ]; then w=1; fi
    echo "$w"
  done <<< "$POOL"
}

# _chief_agents_index <mode> <size> - prints the 0-based pick from POOL
_chief_agents_index() {
  local mode=$1 size=$2 cursor total=0 r w i=0
  case "$STRATEGY" in
    first) echo 0 ;;
    round-robin)
      chief_lock_acquire "$STATE/.agent-select.lock" 10 || { echo "chief-agent: selection lock busy" >&2; return 1; }
      cursor=$(cat "$STATE/agent-cursor-$mode" 2>/dev/null || true)
      [[ $cursor =~ ^[0-9]+$ ]] || cursor=0
      echo $((cursor + 1)) > "$STATE/agent-cursor-$mode"
      chief_lock_release "$STATE/.agent-select.lock"
      echo $((cursor % size)) ;;
    *)
      for w in $(_chief_agents_weights); do total=$((total + w)); done
      [ "$total" -gt 0 ] || { echo "chief-agent: every weight is 0" >&2; return 1; }
      r=$(( ${CHIEF_AGENT_RANDOM:-$((RANDOM * 32768 + RANDOM))} % total ))
      for w in $(_chief_agents_weights); do
        if [ "$r" -lt "$w" ]; then echo "$i"; return 0; fi
        r=$((r - w)); i=$((i + 1))
      done ;;
  esac
}

chief_agent_select() {  # <mode>
  local idx size
  SEL_AGENT=claude SEL_MODEL="" SEL_COMMAND=""
  _chief_agents_read "$1" || return 1
  POOL=${POOL%$'\n'}
  [ -n "$POOL" ] || return 0
  size=$(printf '%s\n' "$POOL" | wc -l)
  idx=$(_chief_agents_index "$1" "$size") || return 1
  IFS=$_SEP read -r SEL_AGENT SEL_MODEL _ SEL_COMMAND <<< "$(printf '%s\n' "$POOL" | sed -n "$((idx + 1))p")"
}
