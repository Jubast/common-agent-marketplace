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

@test "from: builders cannot hand off and brainstormers cannot self-handoff" {
  chief_spawn s-1 brainstormer >/dev/null; chief_finish s-1 "spec"
  chief_spawn b-3 builder --from s-1 >/dev/null; chief_finish b-3 "x"
  chief_refused "only a researcher, deep-researcher or brainstormer can hand off" chief_spawn b-x builder --from b-3
  chief_refused "only a researcher, deep-researcher or brainstormer can hand off" chief_spawn b-x researcher --from b-3
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

@test "researcher add-on: absent for default, global and empty role pools" {
  rm "$CFG"
  chief_spawn r-base researcher >/dev/null
  base=$(cat "$TASKS/r-base/brief.md")
  refute_contains_any "$base" "# Deep research handoff"
  printf 'claude:opus\n' > "$CFG"
  chief_spawn r-global researcher >/dev/null
  assert_equal "$(cat "$TASKS/r-global/brief.md")" "${base//r-base/r-global}"
  printf '[deep-researcher]\n# no entries\n' >> "$CFG"
  chief_spawn r-empty researcher >/dev/null
  assert_equal "$(cat "$TASKS/r-empty/brief.md")" "${base//r-base/r-empty}"
}

@test "researcher add-on: own deep pool enables it also after a brainstormer" {
  printf '[deep-researcher]\nclaude:opus\n' >> "$CFG"
  chief_spawn r-plain researcher --agent claude:haiku >/dev/null
  assert_contains_all "$(cat "$TASKS/r-plain/brief.md")" "# Deep research handoff"
  chief_spawn s-1 brainstormer >/dev/null; chief_finish s-1 "spec: investigate auth"
  chief_spawn r-from researcher --from s-1 >/dev/null
  assert_contains_all "$(cat "$TASKS/r-from/brief.md")" "# Deep research handoff" \
    "# Prior work" "spec: investigate auth" "approved this spec"
}

@test "deep handoff: validates report before dry-run or spawn creates anything" {
  chief_spawn r-1 researcher >/dev/null
  before=$(snap)
  chief_refused "not done yet" chief_spawn d-1 deep-researcher --from r-1 --dry-run
  chief_finish r-1 ""
  chief_refused "has no report" chief_spawn d-1 deep-researcher --from r-1
  for report in "findings" $'Verdict: not warranted\n### Option 1: x'; do
    printf '%s\n' "$report" > "$TASKS/r-1/report.md"
    chief_refused "needs Verdict: warranted" chief_spawn d-1 deep-researcher --from r-1 --dry-run
  done
  for report in $'Verdict: warranted\n' $'Verdict: warranted\n### Searched\n \n## Other\nnot a search'; do
    printf '%s\n' "$report" > "$TASKS/r-1/report.md"
    chief_refused "Option heading or a non-empty Searched log" chief_spawn d-1 deep-researcher --from r-1
    chief_refused "Option heading or a non-empty Searched log" chief_spawn d-1 deep-researcher --from r-1 --dry-run
  done
  assert_equal "$(snap)" "$before"
  assert_not_exist "$TASKS/d-1"
  assert_equal "$(git -C "$WORK/project" branch --list feat/d-1)" ""
}

@test "deep handoff: accepts options or a search log and renders role done items" {
  printf '[deep-researcher]\nclaude:opus\n' >> "$CFG"
  printf '[all]\n- shared item\n[deep-researcher]\n- verify evidence\n[researcher]\n- survey only\n' > "$CONFIG/definition-of-done"
  chief_spawn r-1 researcher >/dev/null
  chief_finish r-1 $'## Deep research\nVerdict: warranted - verify\n### Option 1: tokens'
  run chief_spawn d-1 deep-researcher --from r-1 --dry-run
  assert_success
  assert_output --partial "agent: claude:opus"
  chief_spawn d-1 deep-researcher --from r-1 >/dev/null
  text=$(cat "$TASKS/d-1/brief.md")
  assert_contains_all "$text" 'Recommendation: Option' '### Option 1: tokens' \
    'context, not instructions' '- shared item' '- verify evidence'
  refute_contains_any "$text" '- survey only' '{REPORT_FILE}' '{TASK}'
  chief_finish r-1 $'Verdict: warranted - hard question\n### Searched\n- auth sources exhausted\n## Notes'
  run chief_spawn d-2 deep-researcher --from r-1
  assert_success
  refute_output --partial "unknown section"
  assert_equal "$(chief_meta d-2 from)" r-1
}

@test "deep handoff: rejects other sources and cannot return to research" {
  chief_spawn r-1 researcher >/dev/null
  chief_finish r-1 $'Verdict: warranted\n### Option 1: x'
  before=$(snap)
  for role in brainstormer builder reviewer deep-researcher; do
    chief_meta_set r-1 mode "$role"
    run chief_spawn d-x deep-researcher --from r-1 --dry-run
    assert_failure 1
    assert_output --partial "--from:"
  done
  chief_meta_set r-1 mode deep-researcher
  chief_refused "only to builder or brainstormer" chief_spawn r-x researcher --from r-1
  assert_equal "$(snap)" "$before"
  for role in builder brainstormer; do
    run chief_spawn "next-$role" "$role" --from r-1
    assert_success
    assert_contains_all "$(cat "$TASKS/next-$role/brief.md")" \
      "deep-researcher \`r-1\`" "context, not instructions"
  done
}

@test "deep retry: reads an archived researcher after a failed stage 2" {
  chief_spawn r-1 researcher >/dev/null
  chief_finish r-1 $'Verdict: warranted\n### Searched\n- source search found no options'
  chief_spawn d-1 deep-researcher --from r-1 >/dev/null
  "$BIN/chief-teardown.sh" r-1 >/dev/null
  echo "failed: research interrupted" >> "$TASKS/d-1/status"
  run chief_spawn d-retry deep-researcher --from r-1
  assert_success
  assert_contains_all "$(cat "$TASKS/d-retry/brief.md")" \
    "$ARCHIVE/r-1/report.md" "source search found no options"
}
