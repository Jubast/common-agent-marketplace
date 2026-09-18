#!/usr/bin/env bash
# chief-backend-herdr.sh - herdr backend adapter, verified against a live
# herdr 0.9.0 install (see `herdr --skill` for herdr's own authoritative
# usage guide - re-check it after a herdr upgrade in case the CLI shape
# below has moved on).
#
# herdr organizes terminals as workspace -> tab -> pane, and separately
# tracks a "coding agent" occupying a pane (idle/working/blocked/done/
# unknown). `herdr worktree create` does both the git-worktree-add AND the
# terminal-open in one call, returning the new pane's id
# (workspace-qualified, e.g. "w2:p1") at `.result.root_pane.pane_id` - that
# pane id is exactly what agent commands accept as a target, so it's used
# unmodified as this adapter's endpoint ("herdr:<pane_id>").
#
# A brand-new worktree path triggers Claude Code's own one-time "do you
# trust this folder?" dialog, which leaves `agent start` reporting
# agent_not_ready instead of idle. _chief_herdr_start_agent handles that
# inline (accept the dialog, then wait for idle) rather than treating it as
# a failure - a fresh worktree path hits it on every single spawn.
#
# The brief lives under $CHIEF_HOME (inside the project's main checkout),
# never inside the per-task worktree, so telling claude to go Read it would
# hit Claude Code's own "allow reads outside the working directory?"
# permission dialog on every single spawn too. Sidestepped entirely by
# sending the brief's own CONTENT as the prompt text instead of a path for
# claude to go read.
#
# `herdr agent prompt --wait` can report agent_prompt_stalled - confirmed
# live, reproducibly, right after the trust-dialog path above: the prompt
# text lands in the input line but the trailing Enter doesn't register as a
# submission, so the agent is still genuinely idle with unsent text sitting
# in front of it. herdr's own docs warn not to blindly resubmit the text on
# this error (real risk of the text going in twice) - but a bare follow-up
# Enter keypress (no text) safely submits whatever's already pending;
# confirmed live that this recovers the stall. See _chief_herdr_prompt.

_chief_herdr_workspace_id() {  # <pane-id> -> workspace id ("w2:p1" -> "w2")
  printf '%s' "$1" | cut -d: -f1
}

# _chief_herdr_start_agent <id> <pane-id> - start claude in <pane-id> under
# live name <id>, transparently clearing the first-run trust dialog if it's
# what agent_not_ready turned out to be.
_chief_herdr_start_agent() {
  local id=$1 pane_id=$2
  if herdr agent start "$id" --kind claude --pane "$pane_id" --timeout 30000 >/dev/null 2>&1; then
    return 0
  fi
  local read_out
  read_out=$(herdr agent read "$id" --source recent-unwrapped --lines 40 2>/dev/null)
  case "$read_out" in
    *"trust this folder"*)
      herdr agent send-keys "$id" down >/dev/null 2>&1
      herdr agent send-keys "$id" enter >/dev/null 2>&1
      herdr agent wait "$id" --until idle --timeout 30000 >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

# _chief_herdr_prompt <id> <text> - submit <text> and wait for it to settle.
# On agent_prompt_stalled, does NOT resend <text> (risks it landing twice) -
# sends one bare Enter to submit whatever's already pending, then waits
# again. Only fails if that doesn't get it moving either.
_chief_herdr_prompt() {
  local id=$1 text=$2
  local err
  err=$(herdr agent prompt "$id" "$text" --wait --timeout 120000 2>&1) && return 0
  case "$err" in
    *agent_prompt_stalled*)
      # A stray "--until idle" wait right after send-keys could match the
      # PRE-Enter idle state before it's even processed the keypress - wait
      # for "working" first to prove the turn actually started, then wait
      # again for it to actually settle.
      herdr agent send-keys "$id" enter >/dev/null 2>&1
      herdr agent wait "$id" --until working --timeout 15000 >/dev/null 2>&1 \
        || { echo "chief-backend-herdr: prompt for $id stalled and a follow-up Enter didn't start a turn" >&2; return 1; }
      herdr agent wait "$id" --until idle --until done --until blocked --timeout 120000 >/dev/null 2>&1 \
        || { echo "chief-backend-herdr: prompt for $id started after recovery but never settled" >&2; return 1; }
      return 0
      ;;
    *)
      echo "chief-backend-herdr: 'herdr agent prompt' failed for $id: $err" >&2
      return 1
      ;;
  esac
}

backend_spawn() {
  local id=$1 project_dir=$2 brief_path=$3 branch=$4
  local worktree="$WORKTREES/$id"
  local json pane_id
  json=$(herdr worktree create --cwd "$project_dir" --branch "$branch" --path "$worktree" \
           --label "chief-$id" --trust-repository --no-focus 2>&1) \
    || { echo "chief-backend-herdr: 'herdr worktree create' failed: $json" >&2; return 1; }
  pane_id=$(printf '%s' "$json" | jq -r '.result.root_pane.pane_id // empty')
  [ -n "$pane_id" ] \
    || { echo "chief-backend-herdr: could not read pane id from: $json" >&2; return 1; }

  _chief_herdr_start_agent "$id" "$pane_id" \
    || { echo "chief-backend-herdr: 'herdr agent start' did not become ready for $id" >&2; return 1; }

  _chief_herdr_prompt "$id" "$(cat "$brief_path")" || return 1

  printf '%s\n' "$worktree"
  printf 'herdr:%s\n' "$pane_id"
}

backend_send() {
  local id=$1 text=$2
  case "$text" in
    Enter)  herdr agent send-keys "$id" enter ;;
    Escape) herdr agent send-keys "$id" esc ;;
    C-c)    herdr agent send-keys "$id" ctrl+c ;;
    *)      herdr agent prompt "$id" "$text" ;;
  esac >/dev/null
}

backend_capture() {
  local id=$1
  herdr agent read "$id" --source recent-unwrapped --lines 200 2>/dev/null
}

backend_busy() {
  local id=$1
  herdr agent get "$id" 2>/dev/null | jq -e '.result.agent.agent_status == "working"' >/dev/null
}

backend_kill() {
  local id=$1
  local endpoint pane_id workspace_id
  endpoint=$(chief_meta_get "$id" endpoint 2>/dev/null) || return 0
  pane_id=${endpoint#herdr:}
  [ -n "$pane_id" ] || return 0
  workspace_id=$(_chief_herdr_workspace_id "$pane_id")
  herdr workspace close "$workspace_id" >/dev/null 2>&1 || true
}

backend_relaunch() {
  local id=$1 brief_path=$2
  local project worktree json pane_id
  project=$(chief_meta_get "$id" project)
  worktree=$(chief_meta_get "$id" worktree)
  # --cwd is required here: without it, `herdr worktree open` resolves the
  # repo against ambient server state instead of this specific project -
  # confirmed live to pick up a stale, unrelated repo when omitted.
  json=$(herdr worktree open --cwd "$project" --path "$worktree" --label "chief-$id" --trust-repository --no-focus 2>&1) \
    || { echo "chief-backend-herdr: 'herdr worktree open' failed: $json" >&2; return 1; }
  pane_id=$(printf '%s' "$json" | jq -r '.result.root_pane.pane_id // empty')
  [ -n "$pane_id" ] \
    || { echo "chief-backend-herdr: could not read pane id from: $json" >&2; return 1; }

  _chief_herdr_start_agent "$id" "$pane_id" \
    || { echo "chief-backend-herdr: 'herdr agent start' did not become ready for $id" >&2; return 1; }

  _chief_herdr_prompt "$id" "$(cat "$brief_path")" || return 1

  chief_meta_set "$id" endpoint "herdr:$pane_id"
}
