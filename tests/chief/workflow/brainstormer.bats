# The brainstormer brief and lifecycle content, and the attach hint
# chief-spawn.sh records for it, on a real herdr.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
}

teardown() { chief_herdr_stop; }

# spawn_role <id> <role> [flags...]
spawn_role() {
  local id=$1 role=$2; shift 2
  timeout 90 "$BIN/chief-spawn.sh" "$id" "$WORK/project" --mode "$role" --branch "feat/$id" --intent "shape the idea" "$@"
}

@test "the brief is self-contained, agent-neutral, explicit about confirmation and scope" {
  spawn_role bs-1 brainstormer >/dev/null
  BRIEF=$(cat "$TASKS/bs-1/brief.md")
  has() { [[ $BRIEF == *"$1"* ]]; }
  for needle in "shape the idea" "you talk to the operator directly" "in this pane" \
      "Never ask through \`needs-decision\`" \
      "Never report \`done\` before the operator has explicitly confirmed the spec" \
      "TDD, implementation plans, writing project code, committing, pushing, opening a PR" \
      "$TASKS/bs-1/report.md" "touch $TASKS/bs-1/turn-ended" "working: brainstorming with operator" \
      "done: spec ready" "report \`working: revising spec\` first" "Edit no project files" \
      "**Goal**" "**In scope**" "**Out of scope**" "**Behavior and acceptance criteria**" "**Decisions**" "**Open questions**" \
      "rationale, the options rejected, and what existing code it reuses" "never saw this conversation" \
      "replace any workflow a skill describes"; do
    has "$needle" || { echo "brief lacks: $needle" >&2; return 1; }
  done
  for needle in superpowers writing-plans /brainstorming; do
    ! has "$needle" || { echo "brief has: $needle" >&2; return 1; }
  done
  run grep -qi claude <<< "${BRIEF//CLAUDE.md/}"
  assert_failure
  for ph in TASK SPEC BRANCH REPORT_FILE STATUS_FILE TURN_FILE INBOX_DIR; do
    ! has "{$ph}" || { echo "unfilled {$ph}" >&2; return 1; }
  done
  [ "$(wc -l < "$REPO_ROOT/plugins/chief/templates/brief-brainstormer.md")" -le 55 ]  # stays about 50 lines

  LIFECYCLE=$(cat "$TASKS/bs-1/lifecycle")
  [[ $LIFECYCLE == *"(brainstormer)"* && $LIFECYCLE == *"attach:"* && $LIFECYCLE == *"chief-spawn.sh --from"* ]]
  [[ $LIFECYCLE != *"{TASK_ID}"* ]]
}

@test "spawn prints and records the attach hint for a brainstormer only; dry-run creates nothing" {
  run spawn_role bs-1 brainstormer
  assert_output --partial "attach: herdr workspace focus"
  assert_output --partial "(workspace \"bs-1\")"
  [[ $(chief_meta_get bs-1 attach) == "herdr workspace focus "* ]]
  run spawn_role b-1 builder
  refute_output --partial "attach:"
  assert_equal "$(chief_meta_get b-1 attach 2>/dev/null || true)" ""
  run spawn_role bs-d brainstormer --dry-run
  refute_output --partial "attach:"
  assert_not_exist "$TASKS/bs-d/meta"
}

@test "a brainstormer started as a handoff successor gets the hint too" {
  spawn_role r-1 researcher >/dev/null
  echo "done: found it" >> "$TASKS/r-1/status"
  echo "# findings" > "$TASKS/r-1/report.md"
  run spawn_role bs-3 brainstormer --from r-1
  assert_success
  assert_output --partial "attach:"
  [[ $(chief_meta_get bs-3 attach) == "herdr workspace focus "* ]]
}
