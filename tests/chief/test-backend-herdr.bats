# backends/herdr.sh against a REAL herdr. The agent is the zero-cost stand-in;
# its modes (trust, late, lose-enter, drop, slow-work, never-ready) reproduce the
# situations the adapter has to handle, and herdr_fault (a wrapper around the
# real herdr) replaces one named reply where the real one cannot be provoked.
# Covers what a spawn/relaunch may report as success: only a ready screen
# followed by an observed started turn.
# Not covered: copilot's inline brief echo and the TUI-not-rendered-at-prompt
# paths (the stand-in cannot impersonate copilot to herdr; `agent start` only
# returns once the TUI has rendered).

setup() {
  load lib/common
  chief_common_setup
  chief_project
  export CHIEF_HERDR_START_WAIT=3 CHIEF_HERDR_PROMPT_WAIT=3
  . "$BIN/lib/paths.sh"; . "$BIN/lib/meta.sh"; . "$BIN/lib/agents/agent.sh"
  chief_ensure_dirs
  . "$BIN/lib/backends/herdr.sh"
  chief_meta_set t1 agent claude
  chief_agent_use t1 >/dev/null 2>&1
  WT="$CHIEF_HOME/worktrees/t1"
  BRIEF="You are a researcher: an autonomous worker agent dispatched by Chief. $(printf 'line %s\n' $(seq 1 40))"
  SHORT="Reply with exactly the single word: ok"
}

teardown() { chief_herdr_stop; }

# open_pane <id> - a worktree and an empty shell pane for it (PANE)
open_pane() {
  PANE=$(herdr worktree create --cwd "$WORK/project" --branch "feat/$1" --path "$CHIEF_HOME/worktrees/$1" \
           --label "$1" --trust-repository --no-focus | jq -r '.result.root_pane.pane_id')
}
# started_agent - t1's agent started and ready, by the adapter
started_agent() { open_pane t1; _chief_herdr_start_agent t1 "$PANE" "$WT" >/dev/null 2>&1; }
turn_count() { standin_turns t1 | grep -c 'turn:' || true; }
fault_hits() { cat "$HERDR_FAULTS.$1" 2>/dev/null || echo 0; }
workspace_labels() { herdr workspace list | jq -r '.result.workspaces[].label' | sort | paste -sd' '; }

STALLED='{"error":{"code":"agent_prompt_stalled","message":"agent prompt produced no observed working or blocked state within 5000 ms; current status is idle"}}'
BLOCKED='{"result":{"agent":{"agent_status":"blocked"}}}'

# --- start: readiness comes from the screen ---------------------------------

@test "start: a ready screen -> ready" {
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_success
}

@test "start: herdr itself giving up on a pane that never renders the TUI is a failed start" {
  standin_mode t1 never-ready
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_failure 1
  assert_output --partial "'herdr agent start' failed for t1"
}

@test "start: only the shell line (TUI not rendered) -> not ready after the wait, showing the screen" {
  standin_mode t1 never-ready
  herdr_fault "agent start" 1 after 1 '{"error":{"code":"agent_not_ready","message":"agent t1 is not ready"}}'
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_failure 1
  assert_output --partial "no ready screen"
  assert_output --partial "screen:"
}

@test "start: a late TUI -> start waits and succeeds" {
  standin_mode t1 late=2
  open_pane t1
  CHIEF_HERDR_START_WAIT=10 run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_success
}

@test "start: 'agent start' reporting agent_not_ready does not decide: the screen does" {
  herdr_fault "agent start" 1 after 1 '{"error":{"code":"agent_not_ready","message":"agent t1 is blocked during startup"}}'
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_success
}

@test "start: a pane whose shell is not up yet (agent_pane_busy) is retried, then started" {
  herdr_fault "agent start" 1 before 1 '{"error":{"code":"agent_pane_busy","message":"agent target pane is not an available shell"}}'
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_success
  assert_equal "$(fault_hits 1)" 1
}

@test "start: a pane that stays busy fails after the wait with herdr's error" {
  herdr_fault "agent start" 1000 before 1 '{"error":{"code":"agent_pane_busy","message":"not an available shell"}}'
  open_pane t1
  CHIEF_HERDR_START_WAIT=2 run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_failure 1
  assert_output --partial "agent_pane_busy"
}

@test "start: any other 'agent start' failure fails at once with herdr's error" {
  herdr_fault "agent start" 1000 before 1 '{"error":{"code":"unknown_kind"}}'
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_failure 1
  assert_output --partial "unknown_kind"
  assert_equal "$(fault_hits 1)" 1
}

@test "start: an agent name over 32 chars is rejected by herdr itself" {
  open_pane long
  run _chief_herdr_start_agent build-keycloak-name-with-a-long-tail-of-words "$PANE" "$WT"
  assert_failure 1
  assert_output --partial "failed"
  assert_output --partial "invalid_agent_name"
}

# --- start: folder-trust dialog ---------------------------------------------

@test "trust: the dialog for Chief's own worktree is accepted with down enter, once, then ready" {
  standin_mode t1 trust
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_success
  assert_equal "$(standin_keys t1)" $'down\nenter'
}

@test "trust: a dialog that stays after accepting -> not ready, accepted only once, dialog shown" {
  standin_mode t1 trust trust-sticky
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_failure 1
  assert_output --partial "folder-trust dialog"
  assert_output --partial "Yes, I trust this folder"
  assert_equal "$(standin_keys t1)" $'down\nenter'
}

@test "trust: the dialog for another folder is not accepted" {
  standin_mode t1 "trust=$WORK/elsewhere/other"
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_failure 1
  assert_equal "$(standin_keys t1)" ""
}

# --- prompt: 'blocked' is not 'turn started' --------------------------------

@test "prompt: a reply of blocked -> failure, not retried" {
  started_agent
  herdr_fault "agent prompt" 100 after 0 "$BLOCKED"
  run _chief_herdr_prompt t1 "$BRIEF"
  assert_failure 1
  assert_equal "$(fault_hits 1)" 1
}

@test "prompt: a reply of working -> success, the brief arrived as one turn" {
  started_agent
  run _chief_herdr_prompt t1 "$BRIEF"
  assert_success
  assert_equal "$(turn_count)" 1
}

@test "prompt: herdr rejecting the prompt -> failure with herdr's error" {
  started_agent
  herdr_fault "agent prompt" 100 before 1 '{"error":{"code":"agent_blocked"}}'
  run _chief_herdr_prompt t1 "$BRIEF"
  assert_failure 1
  assert_output --partial "agent_blocked"
}

# --- prompt: stall recovery (herdr's own 5 s stall is real) -------------------

@test "stall: the text landed as a placeholder and Enter was lost -> a bare Enter, never a resend" {
  standin_mode t1 lose-enter=1
  started_agent
  run _chief_herdr_prompt t1 "$BRIEF"
  assert_success
  assert_equal "$(turn_count)" 1
  assert_equal "$(standin_keys t1)" "enter-lost"
}

@test "stall: Enter sent but no turn started -> failure, still no resend" {
  standin_mode t1 lose-enter=2
  started_agent
  run _chief_herdr_prompt t1 "$BRIEF"
  assert_failure 1
  assert_equal "$(turn_count)" 0
  assert_equal "$(standin_keys t1)" $'enter-lost\nenter-lost'
}

@test "stall: the raw head of the brief in the input line -> Enter" {
  standin_mode t1 lose-enter=1
  started_agent
  run _chief_herdr_prompt t1 "$SHORT"
  assert_success
  assert_equal "$(turn_count)" 1
}

@test "stall: a brief already submitted (text above a fresh empty box) -> wait for the turn, no Enter, no resend" {
  standin_mode t1 slow-work=7
  started_agent
  run _chief_herdr_prompt t1 "$SHORT"
  assert_success
  eventually 10 test "$(turn_count)" = 1
  assert_equal "$(standin_keys t1)" ""
}

@test "stall: a brief that never arrived (ready, empty box) -> resent once" {
  standin_mode t1 drop=1
  started_agent
  run _chief_herdr_prompt t1 "$SHORT"
  assert_success
  assert_equal "$(turn_count)" 1
  assert_equal "$(standin_keys t1)" "dropped"
}

@test "stall: stalled again after the resend -> not resent a third time, and says no turn started" {
  standin_mode t1 drop=2
  started_agent
  run _chief_herdr_prompt t1 "$SHORT"
  assert_failure 1
  assert_output --partial "no turn started"
  assert_equal "$(standin_keys t1)" $'dropped\ndropped'
}

@test "stall: a stall at a blocked agent says so" {
  started_agent
  herdr_fault "agent prompt" 100 before 1 "$STALLED"
  herdr_fault "agent get" 100 before 0 "$BLOCKED"
  run _chief_herdr_prompt t1 "$SHORT"
  assert_failure 1
  assert_output --partial "unanswered permission/approval prompt"
}

# --- spawn / relaunch --------------------------------------------------------

spawn_researcher() {
  timeout 120 "$BIN/chief-spawn.sh" "$1" "$WORK/project" --mode researcher --branch "res/$1" --intent x 2>&1
}

@test "spawn: a 'blocked' reply -> non-zero, no 'spawned:', rolled back, only the task's workspace closed" {
  herdr_fault "agent prompt" 100 after 0 "$BLOCKED"
  run spawn_researcher s1
  assert_failure
  refute_output --partial "spawned:"
  assert_not_exist "$CHIEF_HOME/tasks/s1/meta"
  run workspace_labels
  refute_output --partial "s1"
  assert_output --partial "project"
}

@test "spawn: a healthy spawn prints 'spawned:' and creates a workspace labeled with the plain id" {
  run spawn_researcher s2
  assert_success
  assert_output --partial "spawned: s2"
  run workspace_labels
  assert_output --partial "s2"
}

@test "spawn: a lost pre-trust (the dialog for the new worktree) is accepted and the spawn succeeds" {
  standin_mode s4 trust
  run spawn_researcher s4
  assert_success
  assert_output --partial "spawned: s4"
}

# relaunchable_task - r1 spawned, then killed, as chief-control.sh leaves it
relaunchable_task() {
  spawn_researcher r1 >/dev/null
  OLD_ENDPOINT=$(chief_meta_get r1 endpoint)
  chief_agent_use r1 >/dev/null 2>&1
  backend_kill r1
  printf 'brief\n' > "$WORK/brief.md"
}

@test "relaunch: a 'blocked' reply -> fails, closes the task's workspace, records no new endpoint" {
  relaunchable_task
  herdr_fault "agent prompt" 100 after 0 "$BLOCKED"
  run backend_relaunch r1 "$WORK/brief.md"
  assert_failure
  assert_equal "$(chief_meta_get r1 endpoint)" "$OLD_ENDPOINT"
  run workspace_labels
  refute_output --partial "r1"
}

@test "relaunch: a started turn -> success, records the endpoint and reopens the workspace by its plain id" {
  relaunchable_task
  run backend_relaunch r1 "$WORK/brief.md"
  assert_success
  assert_not_equal "$(chief_meta_get r1 endpoint)" "$OLD_ENDPOINT"
  [[ $(chief_meta_get r1 endpoint) == herdr:* ]]
  run workspace_labels
  assert_output --partial "r1"
  assert_equal "$(chief_meta_get r1 label 2>/dev/null || echo none)" none
}

# --- the five adapter functions, end to end -----------------------------------

ws_json() { herdr workspace list; }
linked_count() { ws_json | jq -r --arg root "$1" '[.result.workspaces[]? | select(.worktree.repo_root == $root and .worktree.is_linked_worktree == true)] | length'; }
primary_ws() { ws_json | jq -r --arg root "$1" '.result.workspaces[]? | select(.worktree.repo_root == $root and .worktree.is_linked_worktree == false) | .workspace_id'; }
ws_label() { ws_json | jq -r --arg id "$1" '.result.workspaces[]? | select(.workspace_id == $id) | .label'; }
capture() { herdr agent read "$1" --source recent-unwrapped --lines 200 2>/dev/null; }
idle() { ! backend_busy "$1"; }

# adapter_spawn <id> - backend_spawn as chief-spawn.sh calls it
adapter_spawn() {
  local id=$1
  chief_meta_set "$id" mode builder; chief_meta_set "$id" project "$WORK/project"; chief_meta_set "$id" agent claude
  printf '%s\n' "$SHORT" > "$WORK/brief-$id.md"
  SPAWN_OUT=$(backend_spawn "$id" "$WORK/project" "$WORK/brief-$id.md" "chief/$id")
  chief_meta_set "$id" endpoint "$(sed -n 2p <<< "$SPAWN_OUT")"
  chief_meta_set "$id" worktree "$(sed -n 1p <<< "$SPAWN_OUT")"
}

@test "backend_spawn: worktree and endpoint lines, a primary workspace plus one labeled task workspace, pre-trust, a second task, backend_kill" {
  adapter_spawn t-herdr-1
  assert_equal "$(sed -n 1p <<< "$SPAWN_OUT")" "$CHIEF_HOME/worktrees/t-herdr-1"
  [[ $(sed -n 2p <<< "$SPAWN_OUT") == herdr:* ]]
  assert_exist "$CHIEF_HOME/worktrees/t-herdr-1/.git"
  PRIMARY=$(primary_ws "$WORK/project")
  [ -n "$PRIMARY" ]
  endpoint=$(chief_meta_get t-herdr-1 endpoint)
  assert_equal "$(ws_label "$(_chief_herdr_workspace_id "${endpoint#herdr:}")")" t-herdr-1
  assert_equal "$(chief_meta_get t-herdr-1 label 2>/dev/null || echo none)" none
  assert_equal "$(linked_count "$WORK/project")" 1
  assert_equal "$(jq -r --arg p "$CHIEF_HOME/worktrees/t-herdr-1" '.projects[$p].hasTrustDialogAccepted' "$CLAUDE_CONFIG_DIR/.claude.json")" true

  adapter_spawn t-herdr-2
  assert_equal "$(linked_count "$WORK/project")" 2
  assert_equal "$(primary_ws "$WORK/project")" "$PRIMARY"
  backend_kill t-herdr-2
  assert_equal "$(linked_count "$WORK/project")" 1
  assert_equal "$(primary_ws "$WORK/project")" "$PRIMARY"
}

@test "the pane shows the reply and bypass permissions; backend_busy is idle once it is done" {
  adapter_spawn t-herdr-1
  eventually 20 idle t-herdr-1
  run capture t-herdr-1
  assert_output --partial "ok"
  assert_output --partial "bypass permissions"
}

@test "the input-line check misses text never sent and catches our own text while genuinely in flight" {
  standin_mode t1 lose-enter=1
  started_agent
  box_has() {
    herdr agent read t1 --source detection --lines 40 2>/dev/null | chief_agent_input_line \
      | chief_agent_has_text "$(printf '%s' "$1" | tr -s '[:space:]' ' ' | cut -c1-24)"
  }
  run box_has "never sent to this pane xyz123"
  assert_failure
  ( herdr agent prompt t1 "in flight text for the box" --wait --until working --until blocked --timeout 30000 >/dev/null 2>&1 ) 3>&- &
  caught=0
  for _ in $(seq 1 100); do box_has "in flight text for the box" && { caught=1; break; }; sleep 0.05; done
  wait
  assert_equal "$caught" 1
}

@test "backend_send Escape, backend_kill leaves the worktree and primary workspace, backend_relaunch gives a fresh endpoint" {
  adapter_spawn t-herdr-1
  eventually 20 idle t-herdr-1
  old=$(chief_meta_get t-herdr-1 endpoint)
  PRIMARY=$(primary_ws "$WORK/project")
  run backend_send t-herdr-1 Escape
  assert_success
  backend_kill t-herdr-1
  assert_exist "$CHIEF_HOME/worktrees/t-herdr-1/.git"
  assert_equal "$(linked_count "$WORK/project")" 0
  assert_equal "$(primary_ws "$WORK/project")" "$PRIMARY"
  printf '%s\n' "$SHORT" > "$WORK/brief2.md"
  run backend_relaunch t-herdr-1 "$WORK/brief2.md"
  assert_success
  new=$(chief_meta_get t-herdr-1 endpoint)
  assert_not_equal "$new" "$old"
  assert_equal "$(linked_count "$WORK/project")" 1
  assert_equal "$(ws_label "$(_chief_herdr_workspace_id "${new#herdr:}")")" t-herdr-1
  eventually 20 idle t-herdr-1
  run capture t-herdr-1
  assert_output --partial "ok"
  backend_kill t-herdr-1
  assert_equal "$(linked_count "$WORK/project")" 0
}
