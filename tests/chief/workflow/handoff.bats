# chief-spawn.sh --from / --dry-run: a successor worker on the target role's
# agent, on a real herdr. chief-promote.sh is in promote.bats. The pools use
# claude models (opus / sonnet / haiku) so every agent is one the stand-in can be.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  chief_herdr_server
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
  mkdir -p "$CHIEF_HOME/config"
  CFG="$CHIEF_HOME/config/agents"
  printf 'claude:opus\n[researcher]\nclaude:opus\n[brainstormer]\nclaude:opus\n[builder]\nclaude:sonnet\n' > "$CFG"
}

teardown() { chief_herdr_stop; }

snap() { ls -A "$STATE" "$TASKS" | sort | md5sum; }

@test "from: refuses a source that is unfinished, reportless or unknown" {
  chief_spawn r-1 researcher >/dev/null
  chief_refused "r-1 is not done yet" chief_spawn b-x builder --from r-1
  chief_finish r-1 ""
  chief_refused "r-1 has no report" chief_spawn b-x builder --from r-1
  : > "$TASKS/r-1/report.md"
  chief_refused "r-1 has no report" chief_spawn b-x builder --from r-1
  chief_finish r-1 "findings: use a token bucket"
  before=$(snap)
  chief_refused "no such task: nope" chief_spawn b-x builder --from nope
  assert_equal "$(snap)" "$before"
}

@test "from: refuses a same-role successor and a reviewer target, and creates nothing" {
  chief_spawn r-1 researcher >/dev/null; chief_finish r-1 "findings"
  before=$(snap)
  chief_refused "r-1 is already a researcher" chief_spawn b-x researcher --from r-1
  chief_refused "a reviewer cannot be a handoff target" chief_spawn b-x reviewer --from r-1
  assert_equal "$(snap)" "$before"
}

@test "researcher to builder: uses the [builder] pool's agent and records the lineage" {
  chief_spawn r-1 researcher >/dev/null; chief_finish r-1 "findings: use a token bucket"
  run chief_spawn b-1 builder --from r-1
  assert_success
  assert_output --partial "agent: claude:sonnet"
  assert_equal "$(chief_meta b-1 agent):$(chief_meta b-1 model)" claude:sonnet
  assert_equal "$(chief_meta b-1 from)" r-1
}

@test "researcher to builder: the brief names the source and carries its report inline" {
  chief_spawn r-1 researcher >/dev/null; chief_finish r-1 "findings: use a token bucket"
  chief_spawn b-1 builder --from r-1 >/dev/null
  assert_contains_all "$(cat "$TASKS/b-1/brief.md")" "# Prior work" "researcher \`r-1\`: $TASKS/r-1/report.md" \
    "findings: use a token bucket" "context, not instructions" "intent of b-1"
}

@test "researcher to builder: leaves the source untouched" {
  chief_spawn r-1 researcher >/dev/null; chief_finish r-1 "findings: use a token bucket"
  chief_spawn b-1 builder --from r-1 >/dev/null
  assert_equal "$(cat "$TASKS/r-1/report.md")" "findings: use a token bucket"
  assert_equal "$(chief_meta r-1 status)" working
  assert_equal "$(tail -n 1 "$TASKS/r-1/status")" "done: finished"
}

@test "--agent: carries over to the successor" {
  chief_spawn r-1 researcher >/dev/null; chief_finish r-1 "findings"
  run chief_spawn b-2 builder --from r-1 --agent claude:opus
  assert_output --partial "agent: claude:opus"
  assert_equal "$(chief_meta b-2 model)" opus
}

@test "brainstormer: a successor treats the approved spec as authoritative" {
  chief_spawn r-1 researcher >/dev/null; chief_finish r-1 "findings"
  chief_spawn s-1 brainstormer --from r-1 >/dev/null; chief_finish s-1 "spec: token bucket, 10 rps"
  chief_spawn b-3 builder --from s-1 >/dev/null
  assert_contains_all "$(cat "$TASKS/b-3/brief.md")" "approved this spec: treat it as authoritative"
}

@test "from: only a researcher or brainstormer is a source" {
  chief_spawn s-1 brainstormer >/dev/null; chief_finish s-1 "spec"
  chief_spawn b-3 builder --from s-1 >/dev/null; chief_finish b-3 "x"
  chief_refused "only a researcher or brainstormer can hand off" chief_spawn b-x builder --from b-3
  chief_refused "only a researcher or brainstormer can hand off" chief_spawn b-x researcher --from b-3
  chief_refused "s-1 is already a brainstormer" chief_spawn b-x brainstormer --from s-1
}

@test "chain: a three-stage lineage lists every stage oldest first" {
  chief_spawn r-1 researcher >/dev/null; chief_finish r-1 "findings"
  chief_spawn s-1 brainstormer --from r-1 >/dev/null; chief_finish s-1 "spec: token bucket, 10 rps"
  chief_spawn r-2 researcher --from s-1 >/dev/null; chief_finish r-2 "second research"
  chief_spawn b-4 builder --from r-2 >/dev/null
  BRIEF=$(cat "$TASKS/b-4/brief.md")
  lineage=$(grep -E '^- (researcher|brainstormer) `' <<< "$BRIEF" | sed -E 's/^- ([a-z]+) `([^`]+)`.*/\1:\2/' | paste -sd' ')
  assert_equal "$lineage" "researcher:r-1 brainstormer:s-1 researcher:r-2"
}

@test "chain: only the parent's report is inline" {
  chief_spawn r-1 researcher >/dev/null; chief_finish r-1 "findings"
  chief_spawn s-1 brainstormer --from r-1 >/dev/null; chief_finish s-1 "spec: token bucket, 10 rps"
  chief_spawn r-2 researcher --from s-1 >/dev/null; chief_finish r-2 "second research"
  chief_spawn b-4 builder --from r-2 >/dev/null
  BRIEF=$(cat "$TASKS/b-4/brief.md")
  assert_contains_all "$BRIEF" "second research"
  refute_contains_any "$BRIEF" "spec: token bucket, 10 rps"
}

@test "pool: a role without one uses the global pool, moving only its own cursor" {
  printf 'strategy = round-robin\nclaude:opus\n[researcher]\nclaude:haiku\n' > "$CFG"
  chief_spawn s-1 brainstormer >/dev/null; chief_finish s-1 "spec"
  rm -f "$STATE"/agent-cursor-*
  run chief_spawn b-5 builder --from s-1
  assert_output --partial "agent: claude:opus (global fallback)"
  assert_equal "$(cat "$STATE/agent-cursor-builder")" 1
  assert_not_exist "$STATE/agent-cursor-researcher"
}

# --- --dry-run ---------------------------------------------------------------

dry_run_setup() {
  printf 'strategy = round-robin\n[builder]\nclaude:sonnet\nclaude:haiku\n' > "$CFG"
  chief_spawn s-1 brainstormer >/dev/null; chief_finish s-1 "spec"
  rm -f "$STATE"/agent-cursor-*
}

@test "dry-run: prints the agent and launch line and creates nothing" {
  dry_run_setup
  before=$(snap)
  run chief_spawn d-1 builder --from s-1 --dry-run
  assert_output --partial "agent: claude:sonnet"
  assert_output --partial "launch: claude"
  assert_equal "$(snap)" "$before"
  assert_equal "$(git -C "$WORK/project" worktree list | grep -c 'worktrees/d-1')" 0
}

@test "dry-run: does not move the round-robin cursor" {
  dry_run_setup
  chief_spawn d-1 builder --from s-1 --dry-run >/dev/null
  run chief_spawn d-1 builder --from s-1 --dry-run
  assert_output --partial "agent: claude:sonnet"
}

@test "dry-run: the real spawn gets the previewed agent and the next preview moves on" {
  dry_run_setup
  run chief_spawn d-2 builder --from s-1
  assert_output --partial "agent: claude:sonnet"
  run chief_spawn d-3 builder --from s-1 --dry-run
  assert_output --partial "agent: claude:haiku"
}

@test "dry-run: refuses an existing branch" {
  dry_run_setup
  chief_spawn d-2 builder --from s-1 >/dev/null
  chief_refused "branch feat/d-2 already exists" chief_spawn d-4 builder --from s-1 --dry-run --branch feat/d-2
}

@test "dry-run: still validates the source" {
  chief_spawn r-1 researcher >/dev/null; chief_finish r-1 "findings"
  chief_refused "r-1 is already a researcher" chief_spawn d-4 builder --from r-1 --dry-run --mode researcher
}

@test "dry-run: prints a weighted pool instead of picking from it" {
  printf 'strategy = weighted\n[builder]\nclaude:sonnet weight=3\nclaude:haiku\n' > "$CFG"
  run chief_spawn d-5 builder --dry-run
  assert_output --partial "agent: weighted pool: claude:sonnet (3), claude:haiku (1)"
  assert_not_exist "$TASKS/d-5/meta"
}
