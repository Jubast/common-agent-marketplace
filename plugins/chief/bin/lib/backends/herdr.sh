#!/usr/bin/env bash
# herdr.sh - herdr backend adapter, verified against a live
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
# `herdr agent prompt --wait` can report agent_prompt_stalled for two
# different underlying failures that read identically from the CLI error
# alone, both confirmed live right after the trust-dialog path above:
#   1. the prompt text lands in the input line but the trailing Enter
#      doesn't register as a submission - the agent is genuinely idle with
#      unsent text sitting in front of it. A bare follow-up Enter keypress
#      (no text) safely submits whatever's already pending.
#   2. the prompt text never reaches the input line at all - the box is
#      still empty. A bare Enter here submits nothing; only resending the
#      text recovers it.
# herdr's own docs warn not to blindly resubmit text on this error (real
# risk of it going in twice), which is only a risk for case 1 - so
# _chief_herdr_prompt tells the two apart via herdr's own agent-detection
# state (`herdr agent explain --json`'s "live_prompt_box" rule, which
# renders the box's actual current content) before choosing bare Enter vs.
# resend. See _chief_herdr_prompt and _chief_herdr_prompt_box_empty.
#
# CHIEF_HERDR_SUBMIT_TIMEOUT_MS governs how long backend_spawn/
# backend_relaunch wait for a fresh claude process's very first turn to
# START (reach `working` or `blocked`), handled by _chief_herdr_prompt. It
# does NOT wait for that turn to finish - a first turn on a large task can
# legitimately run long, so this only needs to cover submission and the
# agent visibly starting. backend_send's ordinary mid-task turns don't wait
# at all.
CHIEF_HERDR_SUBMIT_TIMEOUT_MS="${CHIEF_HERDR_SUBMIT_TIMEOUT_MS:-30000}"

_chief_herdr_workspace_id() {  # <pane-id> -> workspace id ("w2:p1" -> "w2")
  printf '%s' "$1" | cut -d: -f1
}

# _chief_herdr_close_pane_by_label <id> - best-effort: find and close
# whatever herdr workspace carries the fixed "chief-<id>" label (the label
# passed to both `herdr worktree create` and `herdr worktree open`) - the
# only id-derived handle guaranteed to survive a failure with no parsed
# pane id. Used by callers that need to clean up a pane before any meta
# record (and so no stored endpoint) exists.
_chief_herdr_close_pane_by_label() {
  local id=$1
  local ws
  ws=$(herdr workspace list 2>/dev/null \
    | jq -r --arg label "chief-$id" '.result.workspaces[]? | select(.label == $label) | .workspace_id' 2>/dev/null) || true
  [ -n "$ws" ] || return 0
  # The trailing `|| true` matters under the caller's `set -e`: without it,
  # a failed `herdr workspace close` on the loop's last line would make the
  # whole pipeline's exit status non-zero and abort the caller right here.
  printf '%s\n' "$ws" | while read -r w; do
    [ -n "$w" ] && herdr workspace close "$w" >/dev/null 2>&1
  done || true
  return 0
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

# _chief_herdr_prompt_box_empty <id> - true (exit 0) only when herdr's own
# agent-detection state affirmatively shows the live input line empty right
# now. Reads the "live_prompt_box" detection rule's region_preview (herdr's
# own rendering of exactly what's in the box, e.g. "❯\n" when empty vs
# "❯ some text\n" when not) via `herdr agent explain --json`. Anything short
# of an affirmative empty reading (the rule is missing, herdr's JSON can't
# be parsed, etc.) returns false - callers must treat "can't tell" as "has
# text", since that's the side with the safe (non-double-submitting)
# recovery.
_chief_herdr_prompt_box_empty() {
  local id=$1
  local body
  body=$(herdr agent explain "$id" --json 2>/dev/null \
    | jq -r '.evaluated_rules[]? | select(.id == "live_prompt_box") | .evidence.region_preview // empty' 2>/dev/null) || return 1
  [ -n "$body" ] || return 1
  body=$(printf '%s' "$body" | tr -d '[:space:]')
  body=${body#❯}
  [ -z "$body" ]
}

# _chief_herdr_prompt <id> <text> - submit <text> and wait only for the
# turn to START (working or blocked), not for it to finish.
#
# `agent_prompt_stalled` covers two genuinely different failures that look
# identical from the CLI error alone (see the file header): <text> never
# reached the pane's input line at all, or it landed but the trailing Enter
# didn't register as a submission. Resending <text> is only safe in the
# first case - in the second it would double-submit. Recovery uses
# _chief_herdr_prompt_box_empty to tell the two apart via herdr's own
# detection state, resending text only when the input line is confirmed
# empty and falling back to the always-safe bare Enter otherwise. Bounded
# to two recovery attempts so a repeat stall fails loudly instead of
# looping forever.
_chief_herdr_prompt() {
  local id=$1 text=$2
  local err attempt
  err=$(herdr agent prompt "$id" "$text" --wait --until working --until blocked \
          --timeout "$CHIEF_HERDR_SUBMIT_TIMEOUT_MS" 2>&1) && return 0
  case "$err" in
    *agent_prompt_stalled*) ;;
    *)
      echo "chief-backend-herdr: 'herdr agent prompt' failed for $id: $err" >&2
      return 1
      ;;
  esac

  for attempt in 1 2; do
    if _chief_herdr_prompt_box_empty "$id"; then
      # Nothing landed - resending is safe, nothing pending to double-submit.
      err=$(herdr agent prompt "$id" "$text" --wait --until working --until blocked \
              --timeout "$CHIEF_HERDR_SUBMIT_TIMEOUT_MS" 2>&1) && return 0
    else
      # Our text is already sitting in the input line; only the Enter didn't
      # register. A stray "--until idle" wait right after send-keys could
      # match the PRE-Enter idle state before it's even processed the
      # keypress - wait for "working" to prove the turn actually started.
      herdr agent send-keys "$id" enter >/dev/null 2>&1
      err=$(herdr agent wait "$id" --until working --timeout 15000 2>&1) && return 0
    fi
    [[ $err == *agent_prompt_stalled* ]] || break
  done
  echo "chief-backend-herdr: prompt for $id stalled and recovery did not start a turn: $err" >&2
  return 1
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

# backend_spawn_cleanup <id> <project-dir> <branch> - best-effort rollback
# after backend_spawn itself failed, or chief-spawn.sh couldn't parse its
# output, before any meta record exists. See backend.sh's contract
# header for the calling convention.
backend_spawn_cleanup() {
  local id=$1 project_dir=$2 branch=$3
  local worktree="$WORKTREES/$id"
  _chief_herdr_close_pane_by_label "$id"
  git -C "$project_dir" worktree remove --force "$worktree" >/dev/null 2>&1 || rm -rf "$worktree"
  git -C "$project_dir" branch -D "$branch" >/dev/null 2>&1 || true
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
    || { echo "chief-backend-herdr: 'herdr worktree open' failed: $json" >&2
         _chief_herdr_close_pane_by_label "$id"
         return 1; }
  pane_id=$(printf '%s' "$json" | jq -r '.result.root_pane.pane_id // empty')
  [ -n "$pane_id" ] \
    || { echo "chief-backend-herdr: could not read pane id from: $json" >&2
         _chief_herdr_close_pane_by_label "$id"
         return 1; }

  _chief_herdr_start_agent "$id" "$pane_id" \
    || { echo "chief-backend-herdr: 'herdr agent start' did not become ready for $id" >&2
         _chief_herdr_close_pane_by_label "$id"
         return 1; }

  _chief_herdr_prompt "$id" "$(cat "$brief_path")" || {
    # The OLD pane was already killed by chief-control.sh before relaunch
    # was called - a failure here leaves the NEW one orphaned with meta's
    # endpoint still pointing at the dead old one.
    _chief_herdr_close_pane_by_label "$id"
    return 1
  }

  chief_meta_set "$id" endpoint "herdr:$pane_id"
}
