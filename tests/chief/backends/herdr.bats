# backends/herdr.sh against a REAL herdr. The agent is the zero-cost stand-in;
# its modes (trust, late, lose-enter, drop, slow-work, never-ready) reproduce the
# situations the adapter has to handle, and chief_herdr_fault (a wrapper around the
# real herdr) replaces one named reply where the real one cannot be provoked.
# Covers what a spawn/relaunch may report as success: only a ready screen
# followed by an observed started turn.
# Not covered: copilot's inline brief echo and the TUI-not-rendered-at-prompt
# paths (the stand-in cannot impersonate copilot to herdr; `agent start` only
# returns once the TUI has rendered).

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  chief_herdr_server
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
fault_hits() { cat "$HERDR_FAULTS.$1" 2>/dev/null || echo 0; }
workspace_labels() { herdr workspace list | jq -r '.result.workspaces[].label' | sort | paste -sd' '; }

STALLED='{"error":{"code":"agent_prompt_stalled","message":"agent prompt produced no observed working or blocked state within 5000 ms; current status is idle"}}'
BLOCKED='{"result":{"agent":{"agent_status":"blocked"}}}'

# --- start: readiness comes from the screen ---------------------------------

@test "start: succeeds on a ready screen" {
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_success
}

@test "start: fails when herdr gives up on a pane that never renders the TUI" {
  standin_never_ready t1
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_failure 1
  assert_output --partial "'herdr agent start' failed for t1"
}

@test "start: fails with the screen shown when only the shell line renders" {
  standin_never_ready t1
  chief_herdr_fault "agent start" 1 after 1 '{"error":{"code":"agent_not_ready","message":"agent t1 is not ready"}}'
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_failure 1
  assert_output --partial "no ready screen"
  assert_output --partial "screen:"
}

@test "start: waits for a late TUI" {
  standin_mode t1 late=2
  open_pane t1
  CHIEF_HERDR_START_WAIT=10 run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_success
}

@test "start: lets the screen, not an agent_not_ready reply, decide" {
  chief_herdr_fault "agent start" 1 after 1 '{"error":{"code":"agent_not_ready","message":"agent t1 is blocked during startup"}}'
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_success
}

@test "start: retries a pane whose shell is not up yet" {
  chief_herdr_fault "agent start" 1 before 1 '{"error":{"code":"agent_pane_busy","message":"agent target pane is not an available shell"}}'
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_success
  assert_equal "$(fault_hits 1)" 1
}

@test "start: fails with herdr's error when the pane stays busy" {
  chief_herdr_fault "agent start" 1000 before 1 '{"error":{"code":"agent_pane_busy","message":"not an available shell"}}'
  open_pane t1
  CHIEF_HERDR_START_WAIT=2 run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_failure 1
  assert_output --partial "agent_pane_busy"
}

@test "start: fails at once on any other 'agent start' error" {
  chief_herdr_fault "agent start" 1000 before 1 '{"error":{"code":"unknown_kind"}}'
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_failure 1
  assert_output --partial "unknown_kind"
  assert_equal "$(fault_hits 1)" 1
}

@test "start: herdr rejects an agent name over 32 characters" {
  open_pane long
  run _chief_herdr_start_agent build-keycloak-name-with-a-long-tail-of-words "$PANE" "$WT"
  assert_failure 1
  assert_output --partial "failed"
  assert_output --partial "invalid_agent_name"
}

# --- start: folder-trust dialog ---------------------------------------------

@test "trust: accepts the dialog for Chief's own worktree once, then is ready" {
  standin_mode t1 trust
  open_pane t1
  run _chief_herdr_start_agent t1 "$PANE" "$WT"
  assert_success
  assert_equal "$(standin_keys t1)" $'down\nenter'
}

@test "trust: a dialog that stays after accepting fails with one acceptance" {
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

@test "prompt: fails without a retry when herdr replies blocked" {
  started_agent
  chief_herdr_fault "agent prompt" 100 after 0 "$BLOCKED"
  run _chief_herdr_prompt t1 "$BRIEF"
  assert_failure 1
  assert_equal "$(fault_hits 1)" 1
}

@test "prompt: succeeds on a working reply, with the brief as one turn" {
  started_agent
  run _chief_herdr_prompt t1 "$BRIEF"
  assert_success
  assert_equal "$(standin_turn_count t1)" 1
}

@test "prompt: fails with herdr's error when herdr rejects it" {
  started_agent
  chief_herdr_fault "agent prompt" 100 before 1 '{"error":{"code":"agent_blocked"}}'
  run _chief_herdr_prompt t1 "$BRIEF"
  assert_failure 1
  assert_output --partial "agent_blocked"
}

# --- prompt: stall recovery (herdr's own 5 s stall is real) -------------------

@test "stall: sends a bare Enter, not a resend, when Enter was lost" {
  standin_mode t1 lose-enter=1
  started_agent
  run _chief_herdr_prompt t1 "$BRIEF"
  assert_success
  assert_equal "$(standin_turn_count t1)" 1
  assert_equal "$(standin_keys t1)" "enter-lost"
}

@test "stall: fails without a resend when the Enter started no turn" {
  standin_mode t1 lose-enter=2
  started_agent
  run _chief_herdr_prompt t1 "$BRIEF"
  assert_failure 1
  assert_equal "$(standin_turn_count t1)" 0
  assert_equal "$(standin_keys t1)" $'enter-lost\nenter-lost'
}

@test "stall: sends Enter when the raw head of the brief sits in the input line" {
  standin_mode t1 lose-enter=1
  started_agent
  run _chief_herdr_prompt t1 "$SHORT"
  assert_success
  assert_equal "$(standin_turn_count t1)" 1
}

@test "stall: waits for the turn of an already submitted brief" {
  standin_mode t1 slow-work=7
  started_agent
  run _chief_herdr_prompt t1 "$SHORT"
  assert_success
  eventually 10 standin_turns_are t1 1
  assert_equal "$(standin_keys t1)" ""
}

@test "stall: resends once when the box is empty" {
  standin_mode t1 drop=1
  started_agent
  run _chief_herdr_prompt t1 "$SHORT"
  assert_success
  assert_equal "$(standin_turn_count t1)" 1
  assert_equal "$(standin_keys t1)" "dropped"
}

@test "stall: stops after one resend and says no turn started" {
  standin_mode t1 drop=2
  started_agent
  run _chief_herdr_prompt t1 "$SHORT"
  assert_failure 1
  assert_output --partial "no turn started"
  assert_equal "$(standin_keys t1)" $'dropped\ndropped'
}

@test "stall: names an unanswered permission prompt at a blocked agent" {
  started_agent
  chief_herdr_fault "agent prompt" 100 before 1 "$STALLED"
  chief_herdr_fault "agent get" 100 before 0 "$BLOCKED"
  run _chief_herdr_prompt t1 "$SHORT"
  assert_failure 1
  assert_output --partial "unanswered permission/approval prompt"
}

# --- spawn / relaunch --------------------------------------------------------

@test "spawn: a blocked reply fails, rolls back and closes only the task's workspace" {
  chief_herdr_fault "agent prompt" 100 after 0 "$BLOCKED"
  run chief_spawn s1 researcher
  assert_failure 1
  refute_output --partial "spawned:"
  assert_not_exist "$CHIEF_HOME/tasks/s1/meta"
  run workspace_labels
  refute_output --partial "s1"
  assert_output --partial "project"
}

@test "spawn: prints 'spawned:' and labels the workspace with the plain id" {
  run chief_spawn s2 researcher
  assert_success
  assert_output --partial "spawned: s2"
  run workspace_labels
  assert_output --partial "s2"
}

@test "spawn: accepts the dialog of a lost pre-trust" {
  standin_mode s4 trust
  run chief_spawn s4 researcher
  assert_success
  assert_output --partial "spawned: s4"
}

# relaunchable_task - r1 spawned, then killed, as chief-control.sh leaves it
relaunchable_task() {
  chief_spawn_quiet r1 --mode researcher
  OLD_ENDPOINT=$(chief_meta_get r1 endpoint)
  chief_agent_use r1 >/dev/null 2>&1
  backend_kill r1
  printf 'brief\n' > "$WORK/brief.md"
}

@test "relaunch: a blocked reply fails, closes the workspace and records no endpoint" {
  relaunchable_task
  chief_herdr_fault "agent prompt" 100 after 0 "$BLOCKED"
  run backend_relaunch r1 "$WORK/brief.md"
  assert_failure 1
  assert_equal "$(chief_meta_get r1 endpoint)" "$OLD_ENDPOINT"
  run workspace_labels
  refute_output --partial "r1"
}

@test "relaunch: records a fresh endpoint and reopens the workspace by its plain id" {
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

# adapter_spawn <id> - backend_spawn as chief-spawn.sh calls it
adapter_spawn() {
  local id=$1
  chief_meta_set "$id" mode builder; chief_meta_set "$id" project "$WORK/project"; chief_meta_set "$id" agent claude
  printf '%s\n' "$SHORT" > "$WORK/brief-$id.md"
  SPAWN_OUT=$(backend_spawn "$id" "$WORK/project" "$WORK/brief-$id.md" "chief/$id")
  chief_meta_set "$id" endpoint "$(sed -n 2p <<< "$SPAWN_OUT")"
  chief_meta_set "$id" worktree "$(sed -n 1p <<< "$SPAWN_OUT")"
}

@test "backend_spawn: prints the worktree and endpoint lines, pre-trusts the worktree" {
  adapter_spawn t-herdr-1
  assert_equal "$(sed -n 1p <<< "$SPAWN_OUT")" "$CHIEF_HOME/worktrees/t-herdr-1"
  [[ $(sed -n 2p <<< "$SPAWN_OUT") == herdr:* ]]
  assert_exist "$CHIEF_HOME/worktrees/t-herdr-1/.git"
  assert_equal "$(chief_trusted "$CHIEF_HOME/worktrees/t-herdr-1")" true
}

@test "backend_spawn: adds one task workspace labeled with the id next to the primary" {
  adapter_spawn t-herdr-1
  PRIMARY=$(primary_ws "$WORK/project")
  [ -n "$PRIMARY" ]
  endpoint=$(chief_meta_get t-herdr-1 endpoint)
  assert_equal "$(ws_label "$(_chief_herdr_workspace_id "${endpoint#herdr:}")")" t-herdr-1
  assert_equal "$(chief_meta_get t-herdr-1 label 2>/dev/null || echo none)" none
  assert_equal "$(linked_count "$WORK/project")" 1
}

@test "backend_kill: closes only its task's workspace" {
  adapter_spawn t-herdr-1
  PRIMARY=$(primary_ws "$WORK/project")
  adapter_spawn t-herdr-2
  assert_equal "$(linked_count "$WORK/project")" 2
  assert_equal "$(primary_ws "$WORK/project")" "$PRIMARY"
  backend_kill t-herdr-2
  assert_equal "$(linked_count "$WORK/project")" 1
  assert_equal "$(primary_ws "$WORK/project")" "$PRIMARY"
}

@test "backend_busy: is idle once the turn is done and the pane shows the reply" {
  adapter_spawn t-herdr-1
  eventually 20 chief_backend_idle t-herdr-1
  run capture t-herdr-1
  assert_output --partial "ok"
  assert_output --partial "bypass permissions"
}

@test "input line: misses text never sent and catches our own text in flight" {
  standin_mode t1 lose-enter=1
  started_agent
  box_has() {
    herdr agent read t1 --source detection --lines 40 2>/dev/null | chief_agent_input_line \
      | chief_agent_has_text "$(printf '%s' "$1" | tr -s '[:space:]' ' ' | cut -c1-24)"
  }
  run box_has "never sent to this pane xyz123"
  assert_failure 1
  ( herdr agent prompt t1 "in flight text for the box" --wait --until working --until blocked --timeout 30000 >/dev/null 2>&1 ) 3>&- &
  prompt_pid=$!
  caught=0
  for _ in $(seq 1 100); do box_has "in flight text for the box" && { caught=1; break; }; sleep 0.05; done
  wait "$prompt_pid" || true  # the prompt itself may fail: the stand-in loses its Enter
  assert_equal "$caught" 1
}

@test "backend_send: delivers Escape" {
  adapter_spawn t-herdr-1
  eventually 20 chief_backend_idle t-herdr-1
  run backend_send t-herdr-1 Escape
  assert_success
}

@test "backend_kill: leaves the worktree and the primary workspace" {
  adapter_spawn t-herdr-1
  eventually 20 chief_backend_idle t-herdr-1
  PRIMARY=$(primary_ws "$WORK/project")
  backend_kill t-herdr-1
  assert_exist "$CHIEF_HOME/worktrees/t-herdr-1/.git"
  assert_equal "$(linked_count "$WORK/project")" 0
  assert_equal "$(primary_ws "$WORK/project")" "$PRIMARY"
}

@test "backend_relaunch: reopens a killed task in a workspace labeled with its id" {
  adapter_spawn t-herdr-1
  eventually 20 chief_backend_idle t-herdr-1
  backend_kill t-herdr-1
  printf '%s\n' "$SHORT" > "$WORK/brief2.md"
  run backend_relaunch t-herdr-1 "$WORK/brief2.md"
  assert_success
  new=$(chief_meta_get t-herdr-1 endpoint)
  assert_equal "$(linked_count "$WORK/project")" 1
  assert_equal "$(ws_label "$(_chief_herdr_workspace_id "${new#herdr:}")")" t-herdr-1
  eventually 20 chief_backend_idle t-herdr-1
  run capture t-herdr-1
  assert_output --partial "ok"
  backend_kill t-herdr-1
  assert_equal "$(linked_count "$WORK/project")" 0
}

# --- the workspace name and its cleanup -----------------------------------

# workspaces - "label|checkout-path" per herdr workspace
workspaces() { herdr workspace list | jq -r '.result.workspaces[] | "\(.label)|\(.worktree.checkout_path // "")"'; }

@test "attach hint: names the plain label" {
  chief_meta_set fix-58 endpoint herdr:w1:p1
  assert_equal "$(backend_attach_hint fix-58)" 'herdr workspace focus w1 (workspace "fix-58")'
}

# cleanup_closes_only <label of the task's workspace>
cleanup_closes_only() {
  chief_spawn_quiet fix-58
  chief_spawn_quiet fix-580
  herdr workspace create --cwd "$WORK" --label fix-58 >/dev/null   # a label twin with no worktree
  [ "$1" = fix-58 ] || herdr workspace rename "$(herdr workspace list | jq -r '.result.workspaces[] | select(.worktree.checkout_path == "'"$WORKTREES/fix-58"'") | .workspace_id')" "$1" >/dev/null
  _chief_herdr_close_task_workspace fix-58
  run workspaces
  refute_line --regexp "\\|$WORKTREES/fix-58\$"
  assert_line "fix-580|$WORKTREES/fix-580"
  assert_line "fix-58|"   # the twin survives
  assert_line "project|$WORK/project"
}
for label in "fix-58" "fix-58 · builder · project"; do
  bats_test_function --description "cleanup: closes only the task's workspace labelled '$label'" \
    -- cleanup_closes_only "$label"
done
