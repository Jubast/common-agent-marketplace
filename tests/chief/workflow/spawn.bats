# chief-spawn.sh on a real herdr: what it renders and records, the arguments it
# refuses, and that a refusal or --dry-run leaves nothing behind. Agent choice
# and launch lines are in spawn-agents.bats, rollback after the backend started
# in spawn-rollback.bats, --from in handoff.bats.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  chief_herdr_server
  . "$BIN/lib/paths.sh"; . "$BIN/lib/meta.sh"
}

teardown() { chief_herdr_stop; }

assert_nothing_left() {  # <id>
  assert_equal "$(chief_leftovers "$1")" 0
  assert_not_exist "$CHIEF_HOME/worktrees/$1"
  assert_equal "$(git -C "$WORK/project" branch --list "feat/$1" | wc -l | tr -d ' ')" 0
}

# --- the rendered brief and lifecycle ---------------------------------------

@test "brief: keeps a multi-line --spec and --intent with sed-delimiter characters" {
  SPEC=$'line one with a | pipe\nline two with an & ampersand\nline three with a \\ backslash'
  INTENT=$'multi-line intent\nwith a | pipe too'
  chief_spawn_quiet t-1 --intent "$INTENT" --spec "$SPEC"
  run cat "$CHIEF_HOME/tasks/t-1/brief.md"
  assert_output --partial "$INTENT"
  assert_output --partial "$SPEC"
}

dod_config() { mkdir -p "$CHIEF_HOME/config"; printf '%s\n' "$@" > "$CHIEF_HOME/config/definition-of-done"; }
dod_section() {  # <id> - the brief from its "# Definition of done" heading on
  sed -n '/^# Definition of done$/,$p' "$CHIEF_HOME/tasks/$1/brief.md"
}

@test "dod: a file with no header gives every role the same items" {
  dod_config '- `make test` passes' '- has a perf test'
  chief_spawn t-b builder >/dev/null
  chief_spawn t-r reviewer >/dev/null
  assert_equal "$(dod_section t-b)" "# Definition of done"$'\n'"The operator's items for a builder:"$'\n'"- \`make test\` passes"$'\n'"- has a perf test"
  assert_contains_all "$(dod_section t-r)" "items for a reviewer:" "- has a perf test"
}

@test "dod: [all] items come first, then the role's own, and other roles' items stay out" {
  dod_config '- before any header' '[builder]' '- builder only' '[all]' '- shared' '[reviewer]' '- reviewer only'
  chief_spawn t-b builder >/dev/null
  assert_equal "$(dod_section t-b | tail -n 3)" "- before any header"$'\n'"- shared"$'\n'"- builder only"
  refute_contains_any "$(dod_section t-b)" "reviewer only"
}

@test "dod: a role-only section reaches that role alone" {
  dod_config '[researcher]' '- cite sources'
  chief_spawn t-r researcher >/dev/null
  chief_spawn t-b builder >/dev/null
  assert_contains_all "$(dod_section t-r)" "- cite sources"
  run grep -x '# Definition of done' "$CHIEF_HOME/tasks/t-b/brief.md"
  assert_failure
}

@test "dod: no heading when the role has no items, the file is empty or it is absent" {
  chief_spawn t-1 builder >/dev/null
  dod_config '[reviewer]' '- reviewer only'
  chief_spawn t-2 builder >/dev/null
  : > "$CHIEF_HOME/config/definition-of-done"
  chief_spawn t-3 builder >/dev/null
  run grep -x '# Definition of done' "$CHIEF_HOME/tasks/t-1/brief.md" "$CHIEF_HOME/tasks/t-2/brief.md" "$CHIEF_HOME/tasks/t-3/brief.md"
  assert_failure
}

@test "dod: an unknown section warns on stderr and its items are ignored" {
  dod_config '[bulider]' '- typo item' '[builder]' '- kept'
  run chief_spawn t-1 builder
  assert_success
  assert_output --partial "unknown section [bulider] ignored"
  assert_contains_all "$(dod_section t-1)" "- kept"
  refute_contains_any "$(dod_section t-1)" "typo item"
}

render_fills_placeholders() {  # <role>
  local id="r-$1"
  chief_spawn "$id" "$1" --spec "Branch: feat/x" >/dev/null
  local brief lifecycle
  brief=$(cat "$CHIEF_HOME/tasks/$id/brief.md") lifecycle=$(cat "$CHIEF_HOME/tasks/$id/lifecycle")
  assert_no_placeholders "$brief"
  assert_no_placeholders "$lifecycle"
  assert_contains_all "$brief" "$CHIEF_HOME/tasks/$id/status" "touch $CHIEF_HOME/tasks/$id/turn-ended" "$CHIEF_HOME/tasks/$id/inbox"
  assert_contains_all "$lifecycle" "$id" "($1)"
}
for role in builder researcher brainstormer reviewer; do
  bats_test_function --description "render: a $role brief and lifecycle have the task's paths filled in" -- render_fills_placeholders "$role"
done

@test "render: the builder lifecycle is an unticked checklist" {
  chief_spawn_quiet t-1
  assert_contains_all "$(cat "$CHIEF_HOME/tasks/t-1/lifecycle")" "- [ ] filed"
}

# --- pre-trust and the recorded agent ---------------------------------------

@test "pre-trust: trusts the task's worktree" {
  chief_spawn_quiet t-1
  assert_equal "$(chief_trusted "$CHIEF_HOME/worktrees/t-1")" true
}

@test "pre-trust: CHIEF_NO_PRETRUST=1 spawns and leaves the claude config alone" {
  rm -f "$CLAUDE_CONFIG_DIR/.claude.json"
  CHIEF_NO_PRETRUST=1 chief_spawn_quiet t-2
  assert_not_exist "$CLAUDE_CONFIG_DIR/.claude.json"
}

@test "meta: records claude as the default agent" {
  chief_spawn_quiet t-1
  assert_equal "$(chief_meta t-1 agent)" claude
}

# --- the attach hint --------------------------------------------------------

@test "attach: a brainstormer prints and records the hint" {
  run chief_spawn bs-1 brainstormer
  assert_output --partial "attach: herdr workspace focus"
  assert_output --partial "(workspace \"bs-1\")"
  [[ $(chief_meta bs-1 attach) == "herdr workspace focus "* ]]
}

@test "attach: a builder prints and records none" {
  run chief_spawn b-1 builder
  refute_output --partial "attach:"
  assert_equal "$(chief_meta b-1 attach 2>/dev/null || true)" ""
}

@test "attach: a brainstormer --dry-run prints none and creates nothing" {
  run chief_spawn bs-d brainstormer --dry-run
  refute_output --partial "attach:"
  assert_not_exist "$CHIEF_HOME/tasks/bs-d/meta"
}

@test "attach: a brainstormer started from a handoff gets the hint too" {
  chief_spawn_quiet r-1 --mode researcher
  echo "done: found it" >> "$CHIEF_HOME/tasks/r-1/status"
  echo "# findings" > "$CHIEF_HOME/tasks/r-1/report.md"
  run chief_spawn bs-3 brainstormer --from r-1
  assert_success
  assert_output --partial "attach:"
  [[ $(chief_meta bs-3 attach) == "herdr workspace focus "* ]]
}

# --- refusals: nothing is left behind ---------------------------------------

@test "branch: refuses a missing --branch" {
  run timeout 90 "$BIN/chief-spawn.sh" t-nobranch "$WORK/project" --mode builder --intent x
  assert_failure 1
  assert_output --partial "--branch is required"
  assert_nothing_left t-nobranch
}

@test "branch: refuses an existing branch and leaves it untouched" {
  git -C "$WORK/project" branch feat/t-exists
  sha=$(git -C "$WORK/project" rev-parse feat/t-exists)
  run chief_spawn t-exists builder
  assert_failure 1
  assert_output --partial "branch feat/t-exists already exists"
  assert_equal "$(git -C "$WORK/project" rev-parse feat/t-exists)" "$sha"
  assert_equal "$(chief_leftovers t-exists)" 0
  assert_not_exist "$CHIEF_HOME/worktrees/t-exists"
}

@test "args: refuses the removed modes ship and scout" {
  for mode in ship scout; do
    run chief_spawn a-x "$mode"
    assert_failure 1
  done
  assert_nothing_left a-x
}

invalid_id_refused() {  # <id> [--dry-run]
  run chief_spawn "$1" builder --branch feat/bad ${2:+"$2"}
  assert_failure 1
  assert_output --partial "invalid task id"
  assert_equal "$(ls "$CHIEF_HOME/tasks" "$CHIEF_HOME/worktrees" "$CHIEF_HOME/state" 2>/dev/null | grep -c "$1\|bad")" 0
}
bats_test_function --description "id: refuses 'Bad_Id' and creates no meta, worktree or lock" -- invalid_id_refused Bad_Id
bats_test_function --description "id: refuses 'Bad_Id' with --dry-run and creates nothing" -- invalid_id_refused Bad_Id --dry-run

@test "dry-run: creates nothing, not even the empty directories" {
  FRESH="$BATS_TEST_TMPDIR/fresh/.chief"
  CHIEF_HOME="$FRESH" run chief_spawn t-dry builder --dry-run
  assert_success
  assert_not_exist "$FRESH"
}

@test "usage: no arguments fails and creates nothing" {
  FRESH="$BATS_TEST_TMPDIR/fresh/.chief"
  CHIEF_HOME="$FRESH" run "$BIN/chief-spawn.sh"
  assert_failure 1
  assert_not_exist "$FRESH"
}
