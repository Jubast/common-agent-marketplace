# chief-spawn.sh brief rendering and agent selection, against a real herdr.
# Covers what a plain `sed -e "s|{SPEC}|$SPEC|g"` substitution cannot survive: a
# --spec/--intent value with embedded newlines and sed-delimiter characters.
# codex/copilot launch lines are checked with --dry-run: the stand-in cannot
# impersonate those TUIs to herdr's detection, so they never really spawn.

setup() {
  load lib/common
  chief_common_setup
  chief_project
  . "$BIN/lib/paths.sh"; . "$BIN/lib/meta.sh"
  CFGDIR="$CHIEF_HOME/config"
}

teardown() { chief_herdr_stop; }

meta() { chief_meta_get "$1" "$2"; }
leftovers() { ls -A "$CHIEF_HOME/tasks/$1" 2>/dev/null | wc -l | tr -d ' '; }
agents_config() { mkdir -p "$CFGDIR"; printf '%b' "$1" > "$CFGDIR/agents"; }
# spawn_flags <id> [flags...] - like `spawn` but its stdout is kept
spawn_flags() {
  local id=$1; shift
  timeout 90 "$BIN/chief-spawn.sh" "$id" "$WORK/project" --mode builder --branch "feat/$id" --intent x "$@"
}

@test "survives a multi-line --spec/--intent with sed-delimiter characters, renders brief and lifecycle, pre-trusts" {
  SPEC=$'line one with a | pipe\nline two with an & ampersand\nline three with a \\ backslash'
  INTENT=$'multi-line intent\nwith a | pipe too'
  spawn t-1 --intent "$INTENT" --spec "$SPEC"
  BRIEF="$CHIEF_HOME/tasks/t-1/brief.md"
  assert_exist "$BRIEF"
  run cat "$BRIEF"
  assert_output --partial "$INTENT"
  assert_output --partial "$SPEC"
  refute_output --partial "{TASK}"
  refute_output --partial "{SPEC}"
  run cat "$CHIEF_HOME/tasks/t-1/lifecycle"
  assert_output --partial "t-1"
  refute_output --partial "{TASK_ID}"
  assert_output --partial "- [ ] filed"
  assert_equal "$(jq -r --arg p "$CHIEF_HOME/worktrees/t-1" '.projects[$p].hasTrustDialogAccepted' "$CLAUDE_CONFIG_DIR/.claude.json")" true
  assert_equal "$(meta t-1 agent)" claude

  # the brief is agent-neutral: the turn-ended protocol is a path, not a Claude hook
  BRIEF_T1=$(cat "$BRIEF")
  for needle in "touch $CHIEF_HOME/tasks/t-1/turn-ended" \
      "the project's checks pass, the work is committed, and the tree is clean" \
      "done: <short commit sha> <one-line summary>" \
      "fix them with new commits (amend only for commit-message findings)" \
      "report \`done\` again" "This brief wins over any skill" \
      "skip a skill's step that would ask a human, push, open a PR, create a worktree, start other agents, or go beyond the spec"; do
    [[ $BRIEF_T1 == *"$needle"* ]] || { echo "brief lacks: $needle" >&2; return 1; }
  done
  for needle in "{TURN_FILE}" "{REVIEW_CHECKLIST}" "Self-review" "conventional-changes"; do
    [[ $BRIEF_T1 != *"$needle"* ]] || { echo "brief has: $needle" >&2; return 1; }
  done
  run grep -qi claude <<< "${BRIEF_T1//CLAUDE.md/}"
  assert_failure
}

@test "CHIEF_NO_PRETRUST=1 still spawns and leaves the claude config untouched" {
  rm -f "$CLAUDE_CONFIG_DIR/.claude.json"
  CHIEF_NO_PRETRUST=1 spawn t-2
  assert_not_exist "$CLAUDE_CONFIG_DIR/.claude.json"
}

@test "--agent agent:model and --model alone are recorded" {
  spawn a-1 --agent claude:opus
  assert_equal "$(meta a-1 agent):$(meta a-1 model)" claude:opus
  spawn a-2 --model sonnet
  assert_equal "$(meta a-2 agent):$(meta a-2 model)" claude:sonnet
}

@test "a codex launch line carries its model and args (dry run)" {
  run spawn_flags a-00 --agent codex:gpt-5 --args "--search" --dry-run
  assert_success
  assert_output --partial "launch: codex --dangerously-bypass-approvals-and-sandbox --model gpt-5 --search"
}

@test "config pool: its profile is used, --model overrides the model, an explicit --agent wins" {
  agents_config 'claude:opus\n'
  spawn a-3
  assert_equal "$(meta a-3 model)" opus
  spawn a-4 --model haiku
  assert_equal "$(meta a-4 model)" haiku
  spawn a-5 --agent claude
  assert_equal "$(meta a-5 model)" ""
}

@test "command override is recorded; an explicit --agent drops it" {
  agents_config 'claude command="claude --dangerously-skip-permissions --foo"\n'
  spawn a-6
  assert_equal "$(meta a-6 command)" "claude --dangerously-skip-permissions --foo"
  spawn a-7 --agent claude
  assert_equal "$(meta a-7 command || echo none)" none
}

@test "the old modes ship and scout are rejected" {
  for mode in ship scout; do
    run timeout 90 "$BIN/chief-spawn.sh" a-x "$WORK/project" --mode $mode --branch feat/a-x --intent x
    assert_failure
  done
}

@test "the agent line reflects --agent and --model; with a pool it keeps the fallback marker" {
  run spawn_flags a-90 --agent claude:haiku --dry-run
  assert_output --partial "agent: claude:haiku"
  run spawn_flags a-91 --agent claude --model opus --dry-run
  assert_output --partial "agent: claude:opus"
  agents_config 'claude:opus\n'
  run spawn_flags a-92 --model haiku --dry-run
  assert_output --partial "agent: claude:haiku (global fallback)"
  run spawn_flags a-92 --model haiku
  assert_output --partial "agent: claude:haiku (global fallback)"
  assert_equal "$(meta a-92 model)" haiku
}

@test "builder and researcher tasks use their own pools" {
  agents_config 'claude:opus\n[builder]\ncodex:gpt-5\n[researcher]\ncopilot\n'
  run spawn_flags a-11 --dry-run
  assert_output --partial "agent: codex:gpt-5"
  run timeout 90 "$BIN/chief-spawn.sh" a-12 "$WORK/project" --mode researcher --branch feat/a-12 --intent x --dry-run
  assert_output --partial "agent: copilot"
}

@test "config args are recorded; --args replaces them; an explicit --agent drops them" {
  agents_config 'claude:opus args="--verbose"\n'
  spawn a-8
  assert_equal "$(meta a-8 args)" "--verbose"
  spawn a-9 --args "--add-dir /x"
  assert_equal "$(meta a-9 args)" "--add-dir /x"
  spawn a-10 --agent claude
  assert_equal "$(meta a-10 args || echo none)" none
}

# fails_with <id> <message> <agents-config> [flags...] - the spawn fails before
# any backend work and leaves nothing behind
fails_with() {
  local id=$1 msg=$2 conf=$3; shift 3
  [ -z "$conf" ] || agents_config "$conf\n"
  run spawn_flags "$id" "$@"
  assert_failure 1
  assert_output --partial "$msg"
  assert_equal "$(leftovers "$id")" 0
  assert_not_exist "$CHIEF_HOME/worktrees/$id"
  assert_equal "$(git -C "$WORK/project" branch --list "feat/$id" | wc -l | tr -d ' ')" 0
}
fails_case() { bats_test_function --description "spawn fails and leaves nothing behind: $1" -- fails_with "${@:2}"; }
fails_case "unknown agent" b-1 "unknown agent 'nope' (available: claude" "" --agent nope
fails_case "bad profile in --agent" b-2 "bad profile" "" --agent 'claude:$(x)'
fails_case "bad profile in --model" b-3 "bad profile" "" --model 'a b'
fails_case "unknown strategy in the config" b-4 "unknown strategy" "strategy = sometimes"
fails_case "command with --args" b-6 "cannot be combined with a model or args" 'claude command="my-claude"' --args "--x"
fails_case "command with --model" b-7 "cannot be combined with a model or args" 'claude command="my-claude"' --model opus
fails_case "command with a configured model" b-8 "cannot be combined with a model or args" 'claude:opus command="my-claude"'
fails_case "quotes in --args" b-9 "may only use letters" "" --args "--add-dir '/a b'"
fails_case "command substitution in --args" b-10 "args" "" --args '$(x)'

@test "herdr: a command with another executable fails and says to use args= or orca" {
  agents_config 'claude command="/opt/wrap.sh --x"\n'
  run spawn_flags b-11
  assert_failure 1
  assert_output --partial "herdr starts the agent's own executable (claude)"
  assert_equal "$(leftovers b-11)" 0
}

@test "herdr: the same executable given by path passes the check and the agent gets the args" {
  agents_config "claude command=\"$STANDIN_BIN/claude --x\"\n"
  run spawn_flags b-12
  assert_success
  refute_output --partial "starts the agent's own executable"
  eventually 10 test -s "$STANDIN_DIR/b-12.args"
  assert_equal "$(cat "$STANDIN_DIR/b-12.args")" "--x"
}

@test "a missing agent CLI fails, says which, and leaves no task files" {
  run env PATH=/usr/bin:/bin timeout 90 "$BIN/chief-spawn.sh" b-5 "$WORK/project" --mode builder --branch feat/b-5 --intent x
  assert_failure 1
  assert_output --partial "the 'claude' CLI is not installed"
  assert_equal "$(leftovers b-5)" 0
}

invalid_id_refused() {  # <id> <extra flag or empty>
  run timeout 90 "$BIN/chief-spawn.sh" "$1" "$WORK/project" --mode builder --branch feat/bad --intent x $2
  assert_failure 1
  assert_output --partial "invalid task id"
  assert_equal "$(ls "$CHIEF_HOME/tasks" "$CHIEF_HOME/worktrees" "$CHIEF_HOME/state" 2>/dev/null | grep -c "$1\|bad")" 0
}
for bad in build-keycloak-name-with-a-long-tail-of-words Bad_Id; do
  for flag in "" --dry-run; do
    bats_test_function --description "the invalid id '$bad' is refused ${flag:-}, creating no meta, worktree or lock" \
      -- invalid_id_refused "$bad" "$flag"
  done
done
