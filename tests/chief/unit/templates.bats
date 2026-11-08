# The brief and lifecycle templates and the dispatch skill, read straight from
# plugins/chief. Only operative tokens are pinned: file paths, status syntax,
# commands and the "never" rules; the rest of the wording is free to change.
# Rendering (placeholders filled in) is checked in workflow/spawn.bats.

setup() {
  load ../lib/common
  TEMPLATES="$REPO_ROOT/plugins/chief/templates"
}

brief() { cat "$TEMPLATES/brief-$1.md"; }

brief_protocol() {  # <role>
  local text; text=$(brief "$1")
  assert_contains_all "$text" '>> {STATUS_FILE}' 'touch {TURN_FILE}' '{INBOX_DIR}/*.msg' '{INBOX_DIR}/handled/'
}
brief_is_agent_neutral() {
  assert_agent_neutral "$(brief "$1")"
  refute_contains_any "$(brief "$1")" superpowers writing-plans conventional-changes /brainstorming
}
lifecycle_names_its_role() {
  local text; text=$(cat "$TEMPLATES/lifecycle-$1.md")
  assert_contains_all "$text" '{TASK_ID}' "($1)"
}
for role in builder researcher brainstormer reviewer; do
  bats_test_function --description "$role brief: reports through the status, turn and inbox files" -- brief_protocol "$role"
  bats_test_function --description "$role brief: is agent-neutral and names no skill suite" -- brief_is_agent_neutral "$role"
  bats_test_function --description "$role lifecycle: names its role and the task id" -- lifecycle_names_its_role "$role"
done

@test "builder brief: the done line carries a sha, and it never pushes or merges" {
  assert_contains_all "$(brief builder)" 'done: <short commit sha> <one-line summary>' 'Never push, never open a PR, never merge' \
    'fix them with new commits (amend only for commit-message findings)' 'This brief wins over any skill'
}

ends_with_one_definition_of_done() {  # <role>
  local text; text=$(brief "$1")
  [ "$(grep -cx '# Definition of done' <<< "$text")" = 1 ]
  [ "$(sed -n '/^# Definition of done$/,$p' <<< "$text" | grep -c '^# ')" = 1 ]
  ! grep -qx '# Done when' <<< "$text"
}
for role in builder researcher brainstormer reviewer; do
  bats_test_function --description "$role brief: ends with the one # Definition of done section" -- ends_with_one_definition_of_done "$role"
done

@test "reviewer brief: reads the project's Definition of done from the base and records its own items under Notes" {
  assert_contains_all "$(brief reviewer)" 'git show <base>:AGENTS.md' 'under `### Builder`' 'under `### Reviewer`' 'Notes:'
}

definition_of_done_is_per_role() {  # <role>
  local subheading; subheading=$(tr a-z A-Z <<< "${1:0:1}")${1:1}
  assert_contains_all "$(brief "$1")" "under \`### $subheading\`" 'under `### All`' '- [ ] n/a - <why>' '{REPORT_FILE}'
}
for role in builder researcher brainstormer reviewer; do
  bats_test_function --description "$role brief: meets its own project items and records one evidence line each" -- definition_of_done_is_per_role "$role"
done

@test "builder brief: readable code, performance trades marked PERF:, project conventions win" {
  assert_contains_all "$(brief builder)" 'Write code for its next reader' 'mark that code with a `PERF:` comment' \
    'set a different bar or marker, follow them; rule 4 still applies'
}

@test "researcher brief: the report goes to REPORT_FILE and nothing is pushed" {
  assert_contains_all "$(brief researcher)" '{REPORT_FILE}' 'Never push to any remote, never open a PR' \
    'This brief wins over any skill'
}

skill_limits() {
  assert_contains_all "$(brief "$1")" "skip a skill's step that would ask a human, push, open a PR, create a worktree, start other agents"
}
for role in builder researcher; do
  bats_test_function --description "$role brief: a skill never makes it ask, push or go beyond the spec" -- skill_limits "$role"
done

@test "brainstormer brief: names six spec sections and wins over a skill" {
  assert_contains_all "$(brief brainstormer)" '**Goal**' '**In scope**' '**Out of scope**' '**Behavior and acceptance criteria**' \
    '**Decisions**' '**Open questions**' 'replace any workflow a skill describes'
}

@test "brainstormer brief: waits for the operator's confirmation, no needs-decision" {
  assert_contains_all "$(brief brainstormer)" '{REPORT_FILE}' 'working: brainstorming with operator' 'done: spec ready' \
    'working: revising spec' 'Never ask through `needs-decision`' \
    'Never report `done` before the operator has explicitly confirmed the spec' 'Edit no project files'
}

@test "reviewer brief: has the nine checklist items" {
  local item
  for item in "Matches intent" "Code and comment quality" "Checks run clean" "No debris" "Scope discipline" \
      "Project docs addressed" "Doc quality" "Commit conventions" "Definition of done met"; do
    assert_contains_all "$(brief reviewer)" "**$item.**"
  done
}

@test "reviewer brief: readability is part of item 2, a missing PERF: comment blocks, nits only suggest" {
  assert_contains_all "$(brief reviewer)" 'carries a `PERF:` comment' \
    'one without it is blocking, a taste-level readability nit is a suggestion' 'judge by those; the conciseness rules below still apply'
}

@test "reviewer brief: fixes the report format, the done lines and the read-only rules" {
  assert_contains_all "$(brief reviewer)" 'Verdict: PASS | FAIL' 'done: round N PASS @<sha7>' 'done: round N FAIL (<n> blocking) @<sha7>' \
    'working: round N' 'git switch --detach <sha>' 'git reset --hard && git clean -fd' \
    'never push, post, comment, merge or edit project files'
}

@test "builder lifecycle: review is the operator's call, teardown discards the reviewer" {
  assert_contains_all "$(cat "$TEMPLATES/lifecycle-builder.md")" 'chief-review.sh <id>' 'chief-teardown.sh' 'also discards its reviewer'
}

@test "researcher lifecycle: hands off with chief-promote.sh or chief-spawn.sh --from" {
  assert_contains_all "$(cat "$TEMPLATES/lifecycle-researcher.md")" 'chief-promote.sh' 'chief-spawn.sh --from'
}

@test "brainstormer lifecycle: tells the operator the attach line" {
  assert_contains_all "$(cat "$TEMPLATES/lifecycle-brainstormer.md")" 'attach:' 'chief-spawn.sh --from'
}

@test "dispatch skill: carries the review loop and no separate reviewer skill exists" {
  assert_contains_all "$(cat "$REPO_ROOT/plugins/chief/skills/dispatch/SKILL.md")" '## The review loop' 'chief-review.sh <builder-id>'
  assert_not_exist "$REPO_ROOT/plugins/chief/skills/reviewer"
}
