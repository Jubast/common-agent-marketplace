# backends/orca.sh against a REAL headless Orca (one server for the file, its
# tests run serially). The agent is the zero-cost stand-in; its modes
# (never-ready, drop, lose-enter) reproduce what the adapter has to survive.
# Orca takes ~8 s over each prompt it cannot see a hook for, hence the size.
# Not covered: codex/copilot launches (the stand-in only impersonates claude).

# bats file_tags=orca
BATS_NO_PARALLELIZE_WITHIN_FILE=true

setup_file() {
  load ../lib/common
  load ../lib/orca
  chief_orca_require
  chief_orca_server
}

teardown_file() { chief_orca_stop; }

teardown() {  # the next test starts with no stand-in of this one running
  local i
  for i in "$ID" "${ID}b" "$LID"; do backend_kill "$i" >/dev/null 2>&1 || true; done
}

setup() {
  load ../lib/common
  load ../lib/orca
  chief_common_setup
  export STANDIN_DIR="$(cat "$BATS_FILE_TMPDIR/orca-dir")/standin"
  export CHIEF_HOME="$WORK/.chief" CHIEF_BACKEND=orca CHIEF_ORCA_START_WAIT=3 CHIEF_ORCA_PROMPT_WAIT=3
  ID="o$BATS_TEST_NUMBER"; LID="l$BATS_TEST_NUMBER"  # LID: chief-spawn.sh wants an id with no meta yet
  P="$WORK/proj$BATS_TEST_NUMBER"
  mkdir -p "$P"
  git -C "$P" init -q -b master
  git -C "$P" commit --allow-empty -q -m init
  . "$BIN/lib/paths.sh"; . "$BIN/lib/meta.sh"; . "$BIN/lib/agents/agent.sh"
  chief_ensure_dirs
  . "$BIN/lib/backends/orca.sh"
  BRIEF="$WORK/brief.md"
  { echo "You are a researcher: an autonomous worker agent dispatched by Chief."; printf 'line %s\n' $(seq 1 40); } > "$BRIEF"
  chief_meta_set "$ID" agent claude
}

# the project's row of `orca repo list`, and its main worktree
repo_count() { orca repo list --json 2>/dev/null | jq -r --arg p "$P" '[.result.repos[]? | select(.path == $p)] | length'; }
child_count() {
  orca worktree list --repo "path:$P" --json 2>/dev/null \
    | jq -r '[.result.worktrees[]? | select(.isMainWorktree == true)][0].childWorktreeIds | length'
}
listed() {  # <worktree> - Orca still lists it
  orca worktree list --repo "path:$P" --json 2>/dev/null | jq -e --arg p "$1" '[.result.worktrees[]? | select(.path == $p)] | length > 0' >/dev/null
}
terminals() { orca terminal list --worktree "path:$1" --json 2>/dev/null | jq -r '[.result.terminals[]?] | length'; }
branch_count() { git -C "$P" branch --list "$1" | wc -l | tr -d ' '; }

# spawned - backend_spawn as chief-spawn.sh drives it, then records what it records
spawned() {
  run --separate-stderr backend_spawn "$ID" "$P" "$BRIEF" "chief/$ID"
  [ "$status" -eq 0 ] || { echo "$stderr" >&2; return 1; }
  WT=$(sed -n 1p <<< "$output"); EP=$(sed -n 2p <<< "$output")
  chief_meta_set "$ID" worktree "$WT"; chief_meta_set "$ID" endpoint "$EP"; chief_meta_set "$ID" project "$P"
}
# rolled_back - nothing of a failed spawn is left in Orca, on disk or in git
rolled_back() {
  assert_not_exist "$HOME/orca/workspaces/$(basename "$P")/$ID"
  run listed "$HOME/orca/workspaces/$(basename "$P")/$ID"
  assert_failure 1
  assert_equal "$(branch_count "chief/$ID")" 0
  assert_equal "$(chief_trusted "$HOME/orca/workspaces/$(basename "$P")/$ID")" unset
}

# --- spawn ---------------------------------------------------------------

@test "spawn: registers the project, nests the task, starts the agent and delivers the brief" {
  assert_equal "$(repo_count)" 0
  spawned
  assert_equal "$(repo_count)" 1
  assert_equal "$(child_count)" 1
  assert_equal "$(dirname "$WT")" "$HOME/orca/workspaces/$(basename "$P")"
  assert_regex "$EP" '^orca:term_'
  assert_equal "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" "chief/$ID"
  assert_equal "$(terminals "$WT")" 1
  assert_equal "$(chief_trusted "$WT")" true
  assert_equal "$(cat "$STANDIN_DIR/$ID.args")" "--dangerously-skip-permissions"
  assert_equal "$(standin_turn_count "$ID")" 1
  assert_output --partial "orca:term_"
  run _chief_orca_screen "${EP#orca:}"
  assert_output --partial "bypass permissions"
}

@test "spawn: a second task registers nothing new; rolling it back leaves the first alone" {
  spawned
  first=$WT
  chief_meta_set "${ID}b" agent claude
  run --separate-stderr backend_spawn "${ID}b" "$P" "$BRIEF" "chief/${ID}b"
  assert_success
  second=$(sed -n 1p <<< "$output")
  assert_equal "$(repo_count)" 1
  assert_equal "$(child_count)" 2
  backend_spawn_cleanup "${ID}b" "$P" "chief/${ID}b"
  run listed "$second"
  assert_failure 1
  assert_not_exist "$second"
  assert_equal "$(branch_count "chief/${ID}b")" 0
  assert_equal "$(child_count)" 1
  run listed "$first"
  assert_success
}

@test "spawn: the task's model and extra args reach the agent" {
  chief_meta_set "$ID" model opus; chief_meta_set "$ID" args "--verbose"
  spawned
  assert_equal "$(cat "$STANDIN_DIR/$ID.args")" "--dangerously-skip-permissions --model opus --verbose"
}

@test "spawn: a project Orca cannot register fails before any worktree exists" {
  rm -rf "$P/.git"
  run --separate-stderr backend_spawn "$ID" "$P" "$BRIEF" "chief/$ID"
  assert_failure 1
  assert_regex "$stderr" "could not register '$P' with Orca"
  assert_not_exist "$HOME/orca/workspaces/$(basename "$P")"
}

@test "spawn: 'orca worktree create' failing names the command" {
  orca repo add --path "$P" --json > /dev/null 2>&1
  rm -rf "$P/.git"
  run --separate-stderr backend_spawn "$ID" "$P" "$BRIEF" "chief/$ID"
  assert_failure 1
  assert_regex "$stderr" "orca worktree create"
}

@test "spawn: a prompt that never landed is resent once" {
  standin_mode "$ID" drop=1
  spawned
  assert_equal "$(standin_turn_count "$ID")" 1
  assert_equal "$(standin_keys "$ID")" dropped
}

@test "spawn: a prompt left in the input line gets a bare Enter, not a resend" {
  standin_mode "$ID" lose-enter=1
  spawned
  assert_equal "$(standin_turn_count "$ID")" 1
  assert_equal "$(standin_keys "$ID")" enter-lost
}

@test "spawn: a recovery Enter that is lost too fails the spawn and rolls it back" {
  standin_mode "$ID" lose-enter=2
  run --separate-stderr backend_spawn "$ID" "$P" "$BRIEF" "chief/$ID"
  assert_failure 1
  assert_regex "$stderr" "still unsubmitted after Enter"
  rolled_back
}

# --- running tasks -------------------------------------------------------

@test "busy and send: busy while a turn runs, idle after; Enter, Escape, text and C-c reach the agent" {
  standin_hold "$ID"
  spawned
  run backend_busy "$ID"
  assert_success
  standin_release "$ID"
  eventually 20 chief_backend_idle "$ID"
  backend_send "$ID" Enter
  backend_send "$ID" Escape
  eventually 10 standin_got_esc "$ID"
  backend_send "$ID" "hello there"
  eventually 20 standin_turns_are "$ID" 2
  assert_equal "$(standin_turns "$ID" | tail -n1)" "turn: hello there"
  backend_send "$ID" C-c
  eventually 10 chief_pid_dead "$(cat "$STANDIN_DIR/$ID.pid")"
}

@test "kill: closes every terminal, keeps the worktree; falls back to the tab with no worktree; no endpoint is a no-op" {
  spawned
  backend_kill "$ID"
  assert_equal "$(terminals "$WT")" 0
  assert_exist "$WT/.git"
  run listed "$WT"
  assert_success

  chief_meta_set "${ID}b" agent claude
  run --separate-stderr backend_spawn "${ID}b" "$P" "$BRIEF" "chief/${ID}b"
  second=$(sed -n 1p <<< "$output")
  chief_meta_set "${ID}b" endpoint "$(sed -n 2p <<< "$output")"
  backend_kill "${ID}b"
  assert_equal "$(terminals "$second")" 0

  run backend_kill "${ID}c"
  assert_success
}

@test "relaunch: a fresh terminal in the same worktree, the brief delivered, the worktree re-trusted" {
  spawned
  backend_kill "$ID"
  chief_agent_release "$ID" "$WT"
  assert_equal "$(chief_trusted "$WT")" unset
  backend_relaunch "$ID" "$BRIEF"
  assert_equal "$(chief_trusted "$WT")" true
  assert_not_equal "$(chief_meta_get "$ID" endpoint)" "$EP"
  assert_equal "$(terminals "$WT")" 1
  assert_equal "$(standin_turn_count "$ID")" 2
  run git -C "$P" worktree list
  assert_output --partial "$WT"
}

@test "relaunch: an agent that is not ready fails and closes the terminal it opened" {
  spawned
  backend_kill "$ID"
  standin_mode "$ID" never-ready
  run --separate-stderr backend_relaunch "$ID" "$BRIEF"
  assert_failure 1
  assert_regex "$stderr" "agent not ready"
  assert_equal "$(terminals "$WT")" 0
}

# --- rollback and teardown -----------------------------------------------

@test "cleanup: rolls back a leftover worktree found by its branch, leaves others, and is a no-op for nothing" {
  spawned
  keep=$WT
  orca repo add --path "$P" --json > /dev/null 2>&1
  chief_meta_set "${ID}c" agent claude
  left=$(orca worktree create --repo "path:$P" --name "${ID}c" --parent-worktree "path:$P" --json 2>/dev/null | jq -r '.result.worktree.path')
  git -C "$left" branch -m "chief/${ID}c"
  backend_spawn_cleanup "${ID}c" "$P" "chief/${ID}c"
  run listed "$left"
  assert_failure 1
  assert_not_exist "$left"
  assert_equal "$(branch_count "chief/${ID}c")" 0
  assert_exist "$keep/.git"
  run backend_spawn_cleanup "${ID}never" "$P" "chief/${ID}never"
  assert_success
}

@test "cleanup: also finds a worktree still on Orca's own branch" {
  orca repo add --path "$P" --json > /dev/null 2>&1
  chief_meta_set "${ID}r" agent claude
  left=$(orca worktree create --repo "path:$P" --name "${ID}r" --parent-worktree "path:$P" --json 2>/dev/null | jq -r '.result.worktree.path')
  backend_spawn_cleanup "${ID}r" "$P" "chief/${ID}r"
  assert_not_exist "$left"
  assert_equal "$(branch_count "${ID}r")" 0
}

@test "teardown: Orca forgets the worktree" {
  spawned
  backend_kill "$ID"
  backend_teardown "$ID" "$P" "$WT"
  run listed "$WT"
  assert_failure 1
  assert_equal "$(child_count)" 0
  assert_equal "$(chief_trusted "$WT")" unset
}

# --- the real lifecycle scripts ------------------------------------------

@test "lifecycle: spawn -> send -> interrupt -> relaunch -> teardown leaves nothing behind" {
  ID=$LID
  run timeout 120 "$BIN/chief-spawn.sh" "$LID" "$P" --mode builder --branch "feat/$LID" --intent test --spec test
  assert_success
  WT=$(chief_meta_get "$LID" worktree)
  EP=$(chief_meta_get "$LID" endpoint)
  assert_regex "$EP" '^orca:term_'
  assert_equal "$(chief_meta_get "$LID" status)" working
  assert_equal "$(chief_meta_get "$LID" attach)" ""  # only a brainstormer has one
  assert_equal "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" "feat/$LID"
  assert_equal "$(child_count)" 1
  eventually 20 chief_backend_idle "$ID"

  run timeout 60 "$BIN/task/chief-send.sh" "$LID" "please continue"
  assert_success
  eventually 20 standin_turns_are "$LID" 2
  assert_regex "$(standin_turns "$LID" | tail -n1)" "chief: instruction waiting"

  run "$BIN/task/chief-control.sh" "$LID" interrupt
  assert_success
  eventually 10 standin_got_esc "$ID"
  assert_equal "$(chief_meta_get "$LID" endpoint)" "$EP"

  run timeout 120 "$BIN/task/chief-control.sh" "$LID" relaunch --note "halfway"
  assert_success
  assert_not_equal "$(chief_meta_get "$LID" endpoint)" "$EP"
  assert_equal "$(terminals "$WT")" 1
  assert_equal "$(standin_turn_count "$LID")" 3

  run "$BIN/chief-teardown.sh" "$LID" --abandon
  assert_success
  assert_not_exist "$WT"
  run listed "$WT"
  assert_failure 1
  assert_equal "$(child_count)" 0
  assert_equal "$(branch_count "feat/$LID")" 0
}

@test "lifecycle: a brainstormer records the Orca attach hint" {
  ID=$LID
  run timeout 120 "$BIN/chief-spawn.sh" "$LID" "$P" --mode brainstormer --branch "feat/$LID" --intent test
  assert_success
  assert_output --partial "attach: in Orca, open worktree $LID (terminal term_"
  assert_regex "$(chief_meta_get "$LID" attach)" "^in Orca, open worktree $LID"
}

@test "spawn: an agent that never shows its screen fails and rolls everything back" {
  ID=$LID
  standin_mode "$LID" never-ready
  run timeout 120 "$BIN/chief-spawn.sh" "$LID" "$P" --mode builder --branch "feat/$LID" --intent test --spec test
  assert_failure 1
  assert_output --partial "agent not ready"
  rolled_back
  assert_equal "$(branch_count "feat/$LID")" 0
  assert_not_exist "$CHIEF_HOME/tasks/$LID/meta"
  assert_equal "$(child_count)" 0
}

# --- zero cost ------------------------------------------------------------

@test "zero cost: in a pane, claude, codex and copilot resolve to stand-ins" {
  spawned
  out="$WORK/which"
  orca terminal create --worktree "path:$WT" --command "type -P claude codex copilot > $out" --json > /dev/null 2>&1
  eventually 10 test -s "$out"
  run cat "$out"
  assert_output "$STANDIN_BIN/claude
$STANDIN_BIN/codex
$STANDIN_BIN/copilot"
}
