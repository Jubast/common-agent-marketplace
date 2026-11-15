# backends/hc.sh against a REAL herdr-core, one core per test, running the
# zero-cost stand-in agent. Its modes (never-ready, drop, lose-enter, trust,
# no-report) reproduce what the adapter has to survive.
# Not covered: codex/copilot launches (the stand-in only impersonates claude).

# bats file_tags=hc

setup() {
  load ../lib/common
  load ../lib/hc
  chief_common_setup
  export CHIEF_HOME="$WORK/.chief" CHIEF_BACKEND=hc CHIEF_HC_START_WAIT=3 CHIEF_HC_PROMPT_WAIT=3
  ID="h$BATS_TEST_NUMBER"; LID="l$BATS_TEST_NUMBER"  # LID: chief-spawn.sh wants an id with no meta yet
  P="$WORK/proj"
  mkdir -p "$P"
  git -C "$P" init -q -b master
  git -C "$P" commit --allow-empty -q -m init
  chief_hc_server
  . "$BIN/lib/paths.sh"; . "$BIN/lib/meta.sh"; . "$BIN/lib/agents/agent.sh"
  chief_ensure_dirs
  . "$BIN/lib/backends/hc.sh"
  BRIEF="$WORK/brief.md"
  { echo "You are a researcher: an autonomous worker agent dispatched by Chief."; printf 'line %s\n' $(seq 1 40); } > "$BRIEF"
  chief_meta_set "$ID" agent claude
}

teardown() { chief_hc_stop; }

# the task's terminals, finished ones too; and the addresses of the live ones
terminals() { hc ls --all --label "chief.task=${1:-$ID}" --json | jq -r '.terminals[] | "\(.address) \(.state)"'; }
live_count() { hc ls --label "chief.task=${1:-$ID}" --json | jq -r '.terminals | length'; }
branch_count() { git -C "$P" branch --list "$1" | wc -l | tr -d ' '; }

# spawned - backend_spawn as chief-spawn.sh drives it, then records what it records
spawned() {
  run --separate-stderr backend_spawn "$ID" "$P" "$BRIEF" "chief/$ID"
  [ "$status" -eq 0 ] || { echo "$stderr" >&2; return 1; }
  WT=$(sed -n 1p <<< "$output"); EP=$(sed -n 2p <<< "$output")
  chief_meta_set "$ID" worktree "$WT"; chief_meta_set "$ID" endpoint "$EP"; chief_meta_set "$ID" project "$P"
}
# rolled_back - nothing of a failed spawn is left in hc, on disk or in git
rolled_back() {
  assert_not_exist "$WORKTREES/$ID"
  assert_equal "$(terminals)" ""
  assert_equal "$(branch_count "chief/$ID")" 0
  assert_equal "$(chief_trusted "$WORKTREES/$ID")" unset
}

# --- spawn ---------------------------------------------------------------

@test "spawn: starts the agent in a labelled terminal and delivers the brief" {
  spawned
  assert_equal "$WT" "$WORKTREES/$ID"
  assert_regex "$EP" '^hc:t[0-9]+$'
  assert_equal "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" "chief/$ID"
  run hc get "${EP#hc:}" --json
  assert_equal "$(jq -r '[.name, .cwd, .state] | join(" ")' <<< "$output")" "$ID $WT live"
  assert_equal "$(jq -r '.labels["chief.task"], .labels["herdr.space"], .labels["herdr.tab"]' <<< "$output" | tr '\n' ' ')" \
    "$ID chief-$ID chief-$ID "
  assert_equal "$(chief_trusted "$WT")" true
  assert_equal "$(cat "$STANDIN_DIR/$ID.args")" "--dangerously-skip-permissions"
  assert_equal "$(standin_turn_count "$ID")" 1
  run hc read "${EP#hc:}"
  assert_output --partial "bypass permissions"
}

@test "spawn: the task's model and extra args reach the agent" {
  chief_meta_set "$ID" model opus; chief_meta_set "$ID" args "--verbose"
  spawned
  assert_equal "$(cat "$STANDIN_DIR/$ID.args")" "--dangerously-skip-permissions --model opus --verbose"
}

@test "spawn: an agent that reports no status gets the brief through the screen" {
  standin_mode "$ID" no-report
  spawned
  assert_equal "$(standin_turn_count "$ID")" 1
}

@test "spawn: a prompt that never landed is resent once" {
  standin_mode "$ID" no-report drop=1
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
  standin_mode "$ID" no-report lose-enter=2
  run --separate-stderr backend_spawn "$ID" "$P" "$BRIEF" "chief/$ID"
  assert_failure 1
  assert_regex "$stderr" "still unsubmitted after Enter"
  rolled_back
}

@test "spawn: a brief that starts with a dash arrives as text" {
  printf -- '-x do the thing\n' > "$BRIEF"
  spawned
  assert_equal "$(standin_turns "$ID")" "turn: -x do the thing"
}

@test "spawn: an agent that never shows its screen fails and rolls everything back" {
  standin_mode "$ID" never-ready
  run --separate-stderr backend_spawn "$ID" "$P" "$BRIEF" "chief/$ID"
  assert_failure 1
  assert_regex "$stderr" "agent .* not ready"
  rolled_back
}

@test "spawn: the folder-trust dialog of its own worktree is accepted once" {
  standin_mode "$ID" trust
  spawned
  assert_equal "$(standin_keys "$ID" | tr '\n' ' ')" "down enter "
  assert_equal "$(standin_turn_count "$ID")" 1
}

@test "spawn: the folder-trust dialog of another folder fails the spawn" {
  standin_mode "$ID" "trust=/somewhere/else"
  run --separate-stderr backend_spawn "$ID" "$P" "$BRIEF" "chief/$ID"
  assert_failure 1
  assert_regex "$stderr" "folder-trust dialog"
  assert_equal "$(standin_keys "$ID")" ""
  rolled_back
}

@test "spawn: a branch that already exists fails before any terminal starts" {
  git -C "$P" branch "chief/$ID"
  run --separate-stderr backend_spawn "$ID" "$P" "$BRIEF" "chief/$ID"
  assert_failure 1
  assert_equal "$(terminals)" ""
}

@test "spawn: inside a core terminal the worker is no child of it" {
  hc run --bg --json --no-parent --name boss -- sleep 600 > /dev/null
  export HC_TERMINAL_ID=$(hc get boss --json | jq -r .address)
  spawned
  assert_equal "$(hc get "${EP#hc:}" --json | jq -r '.parent')" null
}

# --- running tasks -------------------------------------------------------

@test "busy: reports busy while a turn runs and idle after" {
  standin_hold "$ID"
  spawned
  run backend_busy "$ID"
  assert_success
  standin_release "$ID"
  eventually 20 chief_backend_idle "$ID"
}

@test "send: Enter, Escape, text and C-c reach the agent" {
  spawned
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

@test "send: text that starts with a dash is text, not an option" {
  spawned
  eventually 20 chief_backend_idle "$ID"
  backend_send "$ID" "--help me"
  eventually 20 standin_turns_are "$ID" 2
  assert_equal "$(standin_turns "$ID" | tail -n1)" "turn: --help me"
}

@test "kill: removes the terminal and keeps the worktree" {
  spawned
  backend_kill "$ID"
  assert_equal "$(terminals)" ""
  assert_exist "$WT/.git"
}

@test "kill: is a no-op for a task with no terminal" {
  run backend_kill "${ID}c"
  assert_success
}

# the endpoint names an address that belongs to someone else's terminal
foreign_endpoint() {
  hc run --bg --json --no-parent --name other -- sleep 600 > /dev/null
  chief_meta_set "$ID" endpoint "hc:$(hc get other --json | jq -r .address)"
}

@test "kill: never touches a terminal the task does not own" {
  foreign_endpoint
  backend_kill "$ID"
  assert_equal "$(hc get other --json | jq -r .state)" live
}

@test "send: never types into a terminal the task does not own" {
  foreign_endpoint
  run backend_send "$ID" "hello"
  assert_failure
  run backend_busy "$ID"
  assert_failure 1
  assert_equal "$(hc read other)" ""
}

# a terminal hc recovered as a shell after the core lost the agent
lost_agent() {
  hc keep "${EP#hc:}" > /dev/null
  hc server stop > /dev/null
  hc server start > /dev/null
}

@test "send: a shell recovered after a core restart is not the agent" {
  spawned
  lost_agent
  run backend_send "$ID" "rm -rf /"
  assert_failure
  run backend_busy "$ID"
  assert_failure 1
}

@test "relaunch: replaces a recovered shell with a fresh agent in the same worktree" {
  spawned
  lost_agent
  backend_kill "$ID"
  backend_relaunch "$ID" "$BRIEF"
  assert_not_equal "$(chief_meta_get "$ID" endpoint)" "$EP"
  assert_equal "$(live_count)" 1
  assert_equal "$(standin_turn_count "$ID")" 2
}

@test "relaunch: delivers the brief in a fresh terminal and re-trusts the worktree" {
  spawned
  backend_kill "$ID"
  chief_agent_release "$ID" "$WT"
  assert_equal "$(chief_trusted "$WT")" unset
  backend_relaunch "$ID" "$BRIEF"
  assert_equal "$(chief_trusted "$WT")" true
  assert_equal "$(chief_meta_get "$ID" endpoint)" "hc:$(hc ls --label "chief.task=$ID" --json | jq -r '.terminals[0].address')"
  assert_equal "$(live_count)" 1
  assert_equal "$(standin_turn_count "$ID")" 2
  run git -C "$P" worktree list
  assert_output --partial "$WT"
}

@test "relaunch: an agent that is not ready fails and removes the terminal it opened" {
  spawned
  backend_kill "$ID"
  standin_mode "$ID" never-ready
  run --separate-stderr backend_relaunch "$ID" "$BRIEF"
  assert_failure 1
  assert_regex "$stderr" "agent .* not ready"
  assert_equal "$(terminals)" ""
  assert_exist "$WT/.git"
}

# --- rollback and teardown -----------------------------------------------

@test "cleanup: rolls back a spawn that left a worktree, a branch and a terminal, and spares others" {
  spawned
  keep=$WT
  chief_meta_set "${ID}c" agent claude
  git -C "$P" worktree add -q -b "chief/${ID}c" "$WORKTREES/${ID}c"
  hc run --bg --json --no-parent --name "${ID}c" --label "chief.task=${ID}c" -- sleep 600 > /dev/null
  backend_spawn_cleanup "${ID}c" "$P" "chief/${ID}c"
  assert_not_exist "$WORKTREES/${ID}c"
  assert_equal "$(branch_count "chief/${ID}c")" 0
  assert_equal "$(terminals "${ID}c")" ""
  assert_exist "$keep/.git"
  assert_equal "$(live_count)" 1
}

@test "cleanup: is a no-op for a task with nothing to roll back" {
  run backend_spawn_cleanup "${ID}never" "$P" "chief/${ID}never"
  assert_success
}

@test "teardown: releases the pre-trust" {
  spawned
  backend_kill "$ID"
  backend_teardown "$ID" "$P" "$WT"
  assert_equal "$(chief_trusted "$WT")" unset
}

# --- the real lifecycle scripts ------------------------------------------

@test "lifecycle: spawn, send, interrupt, relaunch and teardown leave nothing behind" {
  ID=$LID
  run timeout 120 "$BIN/chief-spawn.sh" "$LID" "$P" --mode builder --branch "feat/$LID" --intent test --spec test
  assert_success
  WT=$(chief_meta_get "$LID" worktree)
  EP=$(chief_meta_get "$LID" endpoint)
  assert_regex "$EP" '^hc:t[0-9]+$'
  assert_equal "$(chief_meta_get "$LID" status)" working
  assert_equal "$(chief_meta_get "$LID" attach)" ""  # only a brainstormer has one
  assert_equal "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" "feat/$LID"
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
  assert_equal "$(live_count "$LID")" 1
  assert_equal "$(standin_turn_count "$LID")" 3

  run "$BIN/chief-teardown.sh" "$LID" --abandon
  assert_success
  assert_not_exist "$WT"
  assert_equal "$(terminals "$LID")" ""
  assert_equal "$(branch_count "feat/$LID")" 0
}

@test "lifecycle: a brainstormer records the hc attach hint" {
  ID=$LID
  run timeout 120 "$BIN/chief-spawn.sh" "$LID" "$P" --mode brainstormer --branch "feat/$LID" --intent test
  assert_success
  assert_output --partial "attach: hc attach $LID"
  assert_regex "$(chief_meta_get "$LID" attach)" "^hc attach $LID"
}

@test "spawn: an agent that never shows its screen rolls everything back through chief-spawn.sh" {
  ID=$LID
  standin_mode "$LID" never-ready
  run timeout 120 "$BIN/chief-spawn.sh" "$LID" "$P" --mode builder --branch "feat/$LID" --intent test --spec test
  assert_failure 1
  assert_output --partial "not ready"
  assert_not_exist "$WORKTREES/$LID"
  assert_equal "$(terminals "$LID")" ""
  assert_equal "$(branch_count "feat/$LID")" 0
  assert_not_exist "$CHIEF_HOME/tasks/$LID/meta"
}
