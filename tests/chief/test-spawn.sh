#!/usr/bin/env bash
# test-spawn.sh - chief-spawn.sh brief rendering, against the mock backend.
# Covers the case a plain `sed -e "s|{SPEC}|$SPEC|g"` substitution cannot
# survive: a --spec/--intent value with embedded newlines and sed-delimiter
# characters (|, &, \).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-spawn:"

WORK=$(mktemp -d)
harness_trap 'rm -rf "$WORK"'
mkdir -p "$WORK/project" && cd "$WORK/project" && git init -q -b master
git commit --allow-empty -q -m init
export CHIEF_HOME="$WORK/.chief"
export CHIEF_BACKEND=mock

SPEC=$'line one with a | pipe\nline two with an & ampersand\nline three with a \\ backslash'
INTENT=$'multi-line intent\nwith a | pipe too'

assert_success "spawn: survives a --spec/--intent with embedded newlines and sed-delimiter characters" -- \
  timeout 10 "$BIN/chief-spawn.sh" t-1 "$WORK/project" --mode ship --branch feat/t-1 --intent "$INTENT" --spec "$SPEC"

BRIEF="$CHIEF_HOME/data/t-1/brief.md"
assert_file_exists "$BRIEF" "spawn: brief was written"
assert_contains "$(cat "$BRIEF")" "$INTENT" "spawn: the multi-line intent is rendered verbatim"
assert_contains "$(cat "$BRIEF")" "$SPEC" "spawn: the multi-line spec is rendered verbatim"
assert_not_contains "$(cat "$BRIEF")" "{TASK}" "spawn: the {TASK} placeholder was filled"
assert_not_contains "$(cat "$BRIEF")" "{SPEC}" "spawn: the {SPEC} placeholder was filled"

LIFECYCLE="$CHIEF_HOME/state/t-1.lifecycle"
assert_file_exists "$LIFECYCLE" "spawn: lifecycle checklist was written"
assert_contains "$(cat "$LIFECYCLE")" "t-1" "spawn: the {TASK_ID} placeholder was filled with the task id"
assert_not_contains "$(cat "$LIFECYCLE")" "{TASK_ID}" "spawn: no unfilled {TASK_ID} placeholder remains"
assert_contains "$(cat "$LIFECYCLE")" "- [ ] filed" "spawn: the ship lifecycle checklist's first step is present"

CFG="$CLAUDE_CONFIG_DIR/.claude.json"
assert_eq "$(jq -r --arg p "$CHIEF_HOME/worktrees/t-1" '.projects[$p].hasTrustDialogAccepted' "$CFG")" "true" "spawn: the task's worktree is pre-trusted"
STATE="$CHIEF_HOME/state"; . "$BIN/lib/meta.sh"
assert_eq "$(chief_meta_get t-1 agent)" "claude" "spawn: the default agent is recorded in meta"

rm -f "$CFG"
assert_success "spawn: CHIEF_NO_PRETRUST=1 still spawns" -- \
  env CHIEF_NO_PRETRUST=1 timeout 10 "$BIN/chief-spawn.sh" t-2 "$WORK/project" --mode ship --branch feat/t-2 --intent x
assert_file_missing "$CFG" "spawn: CHIEF_NO_PRETRUST=1 leaves the claude config untouched"

# the brief is agent-neutral: the turn-ended protocol and review checklist are paths, not Claude hooks/skills
BRIEF_T1=$(cat "$CHIEF_HOME/data/t-1/brief.md")
assert_contains "$BRIEF_T1" "touch $CHIEF_HOME/state/t-1.turn-ended" "brief: tells any agent to touch the turn-ended file"
assert_contains "$BRIEF_T1" "$REPO_ROOT/plugins/chief/skills/reviewer/SKILL.md" "brief: points at the review checklist file"
assert_not_contains "$BRIEF_T1" "{TURN_FILE}" "brief: no unfilled turn placeholder"
assert_not_contains "$BRIEF_T1" "reviewer\` skill" "brief: does not rely on the Claude skill mechanism"

# --- agent selection: flags, config, validation --------------------------
spawn() {  # <id> [flags...]
  local id=$1; shift
  timeout 10 "$BIN/chief-spawn.sh" "$id" "$WORK/project" --mode ship --branch "feat/$id" --intent x "$@"
}
meta() { chief_meta_get "$1" "$2"; }
leftovers() { ls "$CHIEF_HOME/state" | grep -c "^\.\?$1[.]" || true; }

assert_success "spawn: --agent claude:opus" -- spawn a-1 --agent claude:opus
assert_eq "$(meta a-1 agent):$(meta a-1 model)" "claude:opus" "spawn: --agent agent:model is recorded"
assert_success "spawn: --agent codex:gpt-5" -- spawn a-0 --agent codex:gpt-5
assert_eq "$(meta a-0 agent):$(meta a-0 model)" "codex:gpt-5" "spawn: a codex task is recorded"
assert_success "spawn: --model alone" -- spawn a-2 --model sonnet
assert_eq "$(meta a-2 agent):$(meta a-2 model)" "claude:sonnet" "spawn: --model alone keeps the default agent"

mkdir -p "$CHIEF_HOME/config"
printf 'claude:opus\n' > "$CHIEF_HOME/config/agents"
assert_success "spawn: config pool" -- spawn a-3
assert_eq "$(meta a-3 model)" "opus" "spawn: the config's profile is used"
assert_success "spawn: --model over config" -- spawn a-4 --model haiku
assert_eq "$(meta a-4 model)" "haiku" "spawn: --model overrides just the model of the configured profile"
assert_success "spawn: --agent over config" -- spawn a-5 --agent claude
assert_eq "$(meta a-5 model)" "" "spawn: an explicit --agent wins over the config"

printf 'claude:opus command="my-claude --dangerously-skip-permissions"\n' > "$CHIEF_HOME/config/agents"
assert_success "spawn: command override" -- spawn a-6
assert_eq "$(meta a-6 command)" "my-claude --dangerously-skip-permissions" "spawn: the profile's command is recorded in meta"
assert_success "spawn: explicit agent drops the override" -- spawn a-7 --agent claude
assert_eq "$(meta a-7 command || echo none)" "none" "spawn: --agent does not inherit a configured command"
rm "$CHIEF_HOME/config/agents"

printf 'claude:opus\n[builder]\ncodex:gpt-5\n[scout]\ncopilot\n' > "$CHIEF_HOME/config/agents"
assert_success "spawn: ship task with builder/scout pools" -- spawn a-11
assert_eq "$(meta a-11 agent)" "codex" "spawn: a ship task uses the [builder] pool"
assert_success "spawn: scout task with builder/scout pools" -- timeout 10 "$BIN/chief-spawn.sh" a-12 "$WORK/project" --mode scout --branch feat/a-12 --intent x
assert_eq "$(meta a-12 agent)" "copilot" "spawn: a scout task uses the [scout] pool"

printf 'claude:opus args="--verbose"\n' > "$CHIEF_HOME/config/agents"
assert_success "spawn: config args" -- spawn a-8
assert_eq "$(meta a-8 args)" "--verbose" "spawn: the profile's args are recorded in meta"
assert_success "spawn: --args over config" -- spawn a-9 --args "--add-dir /x"
assert_eq "$(meta a-9 args)" "--add-dir /x" "spawn: --args replaces the configured args"
assert_success "spawn: --agent drops configured args" -- spawn a-10 --agent claude
assert_eq "$(meta a-10 args || echo none)" "none" "spawn: --agent does not inherit configured args"
rm "$CHIEF_HOME/config/agents"

fails() {  # <id> <expected message> [flags...] - the spawn fails and leaves nothing behind
  local id=$1 msg=$2; shift 2
  local out; out=$(spawn "$id" "$@" 2>&1); local rc=$?
  assert_eq "$rc" "1" "spawn $id: fails"
  assert_contains "$out" "$msg" "spawn $id: says why"
  assert_eq "$(leftovers "$id")" "0" "spawn $id: no state left behind"
  assert_file_missing "$CHIEF_HOME/worktrees/$id" "spawn $id: no worktree left behind"
  assert_eq "$(git -C "$WORK/project" branch --list "feat/$id" | wc -l | tr -d ' ')" "0" "spawn $id: no branch left behind"
}
fails b-1 "unknown agent 'nope' (available: claude" --agent nope
fails b-2 "bad profile" --agent 'claude:$(x)'
fails b-3 "bad profile" --model 'a b'
printf 'strategy = sometimes\n' > "$CHIEF_HOME/config/agents"
fails b-4 "unknown strategy"
printf 'claude command="my-claude"\n' > "$CHIEF_HOME/config/agents"
fails b-6 "args and command cannot be combined" --args "--x"
rm "$CHIEF_HOME/config/agents"
out=$(PATH=/usr/bin:/bin timeout 10 "$BIN/chief-spawn.sh" b-5 "$WORK/project" --mode ship --branch feat/b-5 --intent x 2>&1); rc=$?
assert_eq "$rc" "1" "spawn: a missing agent CLI fails"
assert_contains "$out" "the 'claude' CLI is not installed" "spawn: and says which CLI"
assert_eq "$(leftovers b-5)" "0" "spawn: and leaves no state behind"

# agent_models, when an adapter defines it, rejects other models
cp -r "$REPO_ROOT/plugins/chief" "$WORK/plugin"
printf '%s\n' '. "$CHIEF_ROOT/bin/lib/agents/claude.sh"' 'agent_models() { printf "%s\n" fast slow; }' > "$WORK/plugin/bin/lib/agents/strict.sh"
sp() { CHIEF_ROOT_OVERRIDE="$WORK/plugin" timeout 10 "$WORK/plugin/bin/chief-spawn.sh" "$1" "$WORK/project" --mode ship --branch "feat/$1" --intent x "${@:2}" 2>&1; }
assert_contains "$(sp c-1 --agent strict:medium)" "unknown model 'medium' for strict (known: fast slow)" "spawn: agent_models rejects an unknown model"
assert_contains "$(sp c-2 --agent strict:fast)" "spawned: c-2" "spawn: agent_models accepts a known model"

harness_summary
