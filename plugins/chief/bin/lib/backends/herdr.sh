#!/usr/bin/env bash
# herdr.sh - herdr backend adapter, verified against a live
# herdr 0.9.1 install (see `herdr --skill` for herdr's own authoritative
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
# agent_not_ready instead of idle - hits on every single spawn. See
# _chief_herdr_start_agent.
#
# The brief lives under $CHIEF_HOME (inside the project's main checkout),
# never inside the per-task worktree, so telling claude to go Read it would
# hit Claude Code's own "allow reads outside the working directory?"
# permission dialog on every single spawn too. Sidestepped entirely by
# sending the brief's own CONTENT as the prompt text instead of a path for
# claude to go read.
#
# `herdr agent prompt --wait` submits text+Enter as one write, then (per
# herdr's own docs) waits up to 5s for observed working/blocked activity
# before reporting `agent_prompt_stalled` - that 5s race is herdr's own
# inherent behavior, not something this adapter controls. A stall can mean
# either of two different things, confirmed live: the text landed but the
# Enter didn't register (safe to recover with a bare Enter), or the text
# never reached the input line at all (a bare Enter here submits nothing;
# only resending recovers it). See _chief_herdr_prompt.
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
# live name <id>. On the first-run trust dialog (agent_not_ready), accept
# it and wait for herdr's own idle state - never guess readiness from a
# fixed sleep.
_chief_herdr_start_agent() {
  local id=$1 pane_id=$2
  herdr agent start "$id" --kind claude --pane "$pane_id" --timeout 30000 >/dev/null 2>&1 && return 0
  herdr agent read "$id" --source recent-unwrapped --lines 40 2>/dev/null | grep -q "trust this folder" || return 1
  herdr agent send-keys "$id" down enter >/dev/null 2>&1
  herdr agent wait "$id" --until idle --timeout 30000 >/dev/null 2>&1
}

# _chief_herdr_prompt_box_has_text <id> <text> - true only when herdr's own
# detection snapshot shows a recognizable prefix of <text> already sitting
# in the live input line. Confirmed live: an untouched box isn't always
# bare - Claude Code fills it with a dim placeholder hint ("Try \"how do I
# ...\"") until the first real prompt, which a bare-emptiness check would
# misread as pending text. Matching against our own submitted text sidesteps
# that: the placeholder can never contain it.
_chief_herdr_prompt_box_has_text() {
  local id=$1 needle
  needle=$(printf '%s' "$2" | tr -s '[:space:]' ' ' | cut -c1-24)
  [ -n "$needle" ] || return 1
  herdr agent read "$id" --source detection --lines 15 2>/dev/null \
    | tr -s '[:space:]' ' ' | grep -qF "$needle"
}

# _chief_herdr_prompt <id> <text> - submit <text> and wait only for the
# turn to START (working or blocked), not for it to finish.
#
# agent_prompt_stalled means herdr's own 5s post-submission race (see file
# header) didn't observe activity - it does not say whether <text> reached
# the input line. Resending is only safe if it didn't (nothing pending to
# double-submit); if it did, only the Enter needs resending.
# _chief_herdr_prompt_box_has_text makes that call from herdr's own state,
# not a guess, and one recovery attempt is taken - a second stall is
# reported, not retried further.
_chief_herdr_prompt() {
  local id=$1 text=$2
  local err
  err=$(herdr agent prompt "$id" "$text" --wait --until working --until blocked \
          --timeout "$CHIEF_HERDR_SUBMIT_TIMEOUT_MS" 2>&1) && return 0
  [[ $err == *agent_prompt_stalled* ]] || {
    echo "chief-backend-herdr: 'herdr agent prompt' failed for $id: $err" >&2
    return 1
  }

  if _chief_herdr_prompt_box_has_text "$id" "$text"; then
    herdr agent send-keys "$id" enter >/dev/null 2>&1
    herdr agent wait "$id" --until working --timeout 15000 >/dev/null 2>&1 && return 0
  else
    herdr agent prompt "$id" "$text" --wait --until working --until blocked \
      --timeout "$CHIEF_HERDR_SUBMIT_TIMEOUT_MS" >/dev/null 2>&1 && return 0
  fi
  echo "chief-backend-herdr: prompt for $id stalled twice, giving up" >&2
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
