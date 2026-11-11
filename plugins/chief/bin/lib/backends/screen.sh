#!/usr/bin/env bash
# screen.sh - the screen-driven parts of a backend adapter (orca, hc, herdr's
# readiness): readiness, trust dialog, prompt delivery. Sourced by the adapter,
# which must define, for its own terminal <handle>:
#   _chief_screen_read <handle>            -> the rendered screen
#   _chief_screen_send <handle> <text>     -> types <text> and Enter (prompts only)
#   _chief_screen_keys <handle> <key>...   -> presses keys (enter, down...)

# _chief_screen_trust_dialog_ours <screen> <worktree> - the screen shows the
# agent's folder-trust dialog for <worktree> (its path wraps across lines)
_chief_screen_trust_dialog_ours() {
  local screen=$1 worktree=$2 flat d
  printf '%s' "$screen" | tr -s '[:space:]' ' ' | grep -Eq -- "$(agent_trust_text)" || return 1
  flat=$(printf '%s' "$screen" | tr -d '[:space:]')
  for d in "$worktree" "$(realpath -m "$worktree")"; do
    [[ $flat == *"$(printf '%s' "$d" | tr -d '[:space:]')"* ]] && return 0
  done
  return 1
}

# _chief_screen_start_ready <handle> <timeout-s> [worktree] - polls the screen
# for agent_ready_text; never guess readiness from a terminal's idle state, it
# reports the bare shell as idle before the agent has started. With <worktree>,
# the folder-trust dialog for it is accepted once (agent_trust_keys); a dialog
# for any other folder is not.
_chief_screen_start_ready() {
  local handle=$1 timeout=$2 worktree=${3:-} screen keys reason waited=0 pressed=0
  keys=$(agent_trust_keys)
  while :; do
    screen=$(_chief_screen_read "$handle")
    printf '%s' "$screen" | grep -Eq -- "$(agent_ready_text)" && return 0
    if [ "$pressed" = 0 ] && [ -n "$worktree" ] && [ -n "$keys" ] \
       && _chief_screen_trust_dialog_ours "$screen" "$worktree"; then
      _chief_screen_keys "$handle" $keys >/dev/null 2>&1
      pressed=1
    fi
    [ "$waited" -lt $((timeout * 2)) ] || break
    sleep 0.5
    waited=$((waited + 1))
  done
  reason="no ready screen after ${timeout}s"
  printf '%s' "$screen" | tr -s '[:space:]' ' ' | grep -Eq -- "$(agent_trust_text)" \
    && reason="stopped at the folder-trust dialog"
  echo "chief-backend-$CHIEF_BACKEND: agent $handle not ready ($reason); screen:" >&2
  printf '%s\n' "$screen" | grep -v '^[[:space:]]*$' | tail -5 | sed 's/^/  /' >&2
  return 1
}

# _chief_screen_prompt <handle> <text> <wait-s> - sends <text>, then settles it.
_chief_screen_prompt() {
  _chief_screen_send "$1" "$2" \
    || { echo "chief-backend-$CHIEF_BACKEND: sending the prompt to $1 failed" >&2; return 1; }
  _chief_screen_settle "$@"
}

# _chief_screen_settle <handle> <text> <wait-s> - checks the screen after <text>
# was sent: the text (or the agent's pasted-text placeholder) showing up means
# it landed. If it still sits in the live input line a bare Enter submits it,
# and the prompt counts as sent only once it has left that line; not landed
# within <wait-s> seconds is resent once. Does NOT wait for the turn to
# finish - a first turn on a large task can legitimately run long.
_chief_screen_settle() {
  local handle=$1 text=$2 wait=$3
  local needle screen waited=0 limit=$(( wait * 2 ))
  needle=$(printf '%s' "$text" | tr -s '[:space:]' ' ' | cut -c1-24)
  while [ "$waited" -lt "$limit" ]; do
    screen=$(_chief_screen_read "$handle")
    if printf '%s' "$screen" | chief_agent_has_text "$needle"; then
      printf '%s\n' "$screen" | chief_agent_input_line | chief_agent_has_text "$needle" || return 0
      _chief_screen_keys "$handle" enter >/dev/null 2>&1
      _chief_screen_wait_submitted "$handle" "$needle" "$wait" && return 0
      echo "chief-backend-$CHIEF_BACKEND: prompt for $handle still unsubmitted after Enter" >&2
      return 1
    fi
    sleep 0.5
    waited=$((waited + 1))
  done
  _chief_screen_send "$handle" "$text" \
    || { echo "chief-backend-$CHIEF_BACKEND: sending the prompt to $handle failed" >&2; return 1; }
}

# _chief_screen_wait_submitted <handle> <needle> <wait-s> - polls until the
# prompt has left the live input line
_chief_screen_wait_submitted() {
  local handle=$1 needle=$2 waited=0
  while [ "$waited" -lt $(( $3 * 2 )) ]; do
    _chief_screen_read "$handle" | chief_agent_input_line | chief_agent_has_text "$needle" || return 0
    sleep 0.5
    waited=$((waited + 1))
  done
  return 1
}
