# Which agent chief-spawn.sh picks and how it launches it, on a real herdr:
# --agent, --model, --args, the config pools and command= overrides. codex and
# copilot launch lines are checked with --dry-run: the stand-in cannot
# impersonate those TUIs to herdr's detection, so they never really spawn.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  chief_herdr_server
  . "$BIN/lib/paths.sh"; . "$BIN/lib/meta.sh"
  CFGDIR="$CHIEF_HOME/config"
}

teardown() { chief_herdr_stop; }

agents_config() { mkdir -p "$CFGDIR"; printf '%b' "$1" > "$CFGDIR/agents"; }
# dry <flags...> - what a builder spawn with these flags would run
dry() { run chief_spawn a-dry builder --dry-run "$@"; assert_success; }

# --- --agent and --model ------------------------------------------------------

@test "--agent: records agent and model from agent:model" {
  chief_spawn_quiet a-1 --agent claude:opus
  assert_equal "$(chief_meta a-1 agent):$(chief_meta a-1 model)" claude:opus
}

@test "--model: alone is recorded on the default agent" {
  chief_spawn_quiet a-2 --model sonnet
  assert_equal "$(chief_meta a-2 agent):$(chief_meta a-2 model)" claude:sonnet
}

@test "--agent: a codex launch line carries its model and args" {
  dry --agent codex:gpt-5 --args "--search"
  assert_output --partial "launch: codex --dangerously-bypass-approvals-and-sandbox --model gpt-5 --search"
}

@test "agent line: shows --agent claude:haiku" {
  dry --agent claude:haiku
  assert_output --partial "agent: claude:haiku"
}

@test "agent line: --model replaces the model of --agent claude" {
  dry --agent claude --model opus
  assert_output --partial "agent: claude:opus"
}

@test "agent line: a pool keeps the global-fallback marker under --model" {
  agents_config 'claude:opus\n'
  dry --model haiku
  assert_output --partial "agent: claude:haiku (global fallback)"
}

# --- the config pools -------------------------------------------------------

@test "pool: records the configured model and args" {
  agents_config 'claude:opus args="--verbose"\n'
  chief_spawn_quiet a-3
  assert_equal "$(chief_meta a-3 model):$(chief_meta a-3 args)" "opus:--verbose"
}

@test "pool: records a configured command" {
  agents_config 'claude command="claude --dangerously-skip-permissions --foo"\n'
  chief_spawn_quiet a-6
  assert_equal "$(chief_meta a-6 command)" "claude --dangerously-skip-permissions --foo"
}

@test "pool: each role uses its own pool" {
  agents_config 'claude:opus\n[builder]\ncodex:gpt-5\n[researcher]\ncopilot\n'
  dry
  assert_output --partial "agent: codex:gpt-5"
  run chief_spawn a-12 researcher --dry-run
  assert_output --partial "agent: copilot"
}

@test "pool: --model overrides the configured model" {
  agents_config 'claude:opus\n'
  dry --model haiku
  assert_output --partial "launch: claude --dangerously-skip-permissions --model haiku"
}

@test "pool: --args replaces the configured args" {
  agents_config 'claude:opus args="--verbose"\n'
  dry --args "--add-dir /x"
  assert_output --partial "--add-dir /x"
  refute_output --partial "--verbose"
}

@test "pool: an explicit --agent drops the configured model and args" {
  agents_config 'claude:opus args="--verbose"\n'
  dry --agent claude
  assert_output --partial "launch: claude --dangerously-skip-permissions"
  refute_output --partial "opus"
  refute_output --partial "--verbose"
}

@test "pool: an explicit --agent drops the configured command" {
  agents_config 'claude command="claude --dangerously-skip-permissions --foo"\n'
  dry --agent claude
  refute_output --partial "--foo"
}

# --- refusals: nothing is left behind -----------------------------------------

# fails_with <id> <message> <agents-config> [flags...] - the spawn fails before
# any backend work and leaves nothing behind
fails_with() {
  local id=$1 msg=$2 conf=$3; shift 3
  [ -z "$conf" ] || agents_config "$conf\n"
  run chief_spawn "$id" builder "$@"
  assert_failure 1
  assert_output --partial "$msg"
  assert_equal "$(chief_leftovers "$id")" 0
  assert_not_exist "$CHIEF_HOME/worktrees/$id"
  assert_equal "$(git -C "$WORK/project" branch --list "feat/$id" | wc -l | tr -d ' ')" 0
}
fails_case() { bats_test_function --description "spawn: refuses $1 and leaves nothing behind" -- fails_with "${@:2}"; }
fails_case "an unknown agent" b-1 "unknown agent 'nope' (available: claude" "" --agent nope
fails_case "a bad profile in --agent" b-2 "bad profile" "" --agent 'claude:$(x)'
fails_case "a bad profile in --model" b-3 "bad profile" "" --model 'a b'
fails_case "an unknown strategy in the config" b-4 "unknown strategy" "strategy = sometimes"
fails_case "a command with --args" b-6 "cannot be combined with a model or args" 'claude command="my-claude"' --args "--x"
fails_case "a command with --model" b-7 "cannot be combined with a model or args" 'claude command="my-claude"' --model opus
fails_case "a command with a configured model" b-8 "cannot be combined with a model or args" 'claude:opus command="my-claude"'
fails_case "quotes in --args" b-9 "may only use letters" "" --args "--add-dir '/a b'"
fails_case "command substitution in --args" b-10 "args" "" --args '$(x)'

@test "command: a different executable fails on herdr and says to use args= or orca" {
  agents_config 'claude command="/opt/wrap.sh --x"\n'
  run chief_spawn b-11 builder
  assert_failure 1
  assert_output --partial "herdr starts the agent's own executable (claude)"
  assert_equal "$(chief_leftovers b-11)" 0
}

@test "agent CLI: a missing one fails, says which, and leaves no task files" {
  run env PATH=/usr/bin:/bin timeout 90 "$BIN/chief-spawn.sh" b-5 "$WORK/project" --mode builder --branch feat/b-5 --intent x
  assert_failure 1
  assert_output --partial "the 'claude' CLI is not installed"
  assert_equal "$(chief_leftovers b-5)" 0
}

# --- what the agent process receives on herdr -------------------------------

@test "launch: a model and extra args reach the agent's own executable" {
  chief_spawn_quiet ta --agent claude:gpt-5 --args "--search"
  eventually 10 test -s "$STANDIN_DIR/ta.args"
  assert_equal "$(cat "$STANDIN_DIR/ta.args")" "--dangerously-skip-permissions --model gpt-5 --search"
}

@test "launch: a command with the same executable by path supplies the args" {
  agents_config "claude command=\"$STANDIN_BIN/claude --x\"\n"
  run chief_spawn b-12 builder
  assert_success
  refute_output --partial "starts the agent's own executable"
  eventually 10 test -s "$STANDIN_DIR/b-12.args"
  assert_equal "$(cat "$STANDIN_DIR/b-12.args")" "--x"
}

@test "launch: a bare command override passes no arguments" {
  agents_config 'claude command="claude"\n'
  chief_spawn_quiet tb
  eventually 10 test -e "$STANDIN_DIR/tb.args"
  assert_equal "$(cat "$STANDIN_DIR/tb.args")" ""
}
