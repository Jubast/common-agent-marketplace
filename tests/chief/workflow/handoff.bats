# chief-spawn.sh --from / --dry-run and the chief-promote.sh wrapper: a
# successor worker on the target role's agent, on a real herdr. The pools use
# claude models (opus / sonnet / haiku) so every agent is one the stand-in can be.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
  mkdir -p "$CHIEF_HOME/config"
  CFG="$CHIEF_HOME/config/agents"
  printf 'claude:opus\n[researcher]\nclaude:opus\n[brainstormer]\nclaude:opus\n[builder]\nclaude:sonnet\n' > "$CFG"
  PROMOTE="$BIN/task/chief-promote.sh"
}

teardown() { chief_herdr_stop; }

hspawn() {  # <id> <role> [flags...]
  local id=$1 role=$2; shift 2
  timeout 90 "$BIN/chief-spawn.sh" "$id" "$WORK/project" --mode "$role" --branch "feat/$id" --intent "intent of $id" "$@"
}
finish() {  # <id> [report text] - the worker reports done and writes its report
  echo "done: finished" >> "$TASKS/$1/status"
  [ "${2-x}" = "" ] || echo "${2:-report of $1}" > "$TASKS/$1/report.md"
}
meta() { chief_meta_get "$1" "$2"; }
refused() {  # <reason> <cmd...> - exits nonzero and says why
  local reason=$1; shift
  run "$@"
  assert_failure
  assert_output --partial "$reason"
}
snap() { ls -A "$STATE" "$TASKS" | sort | md5sum; }

@test "the researcher brief: the brief wins over any skill, names the steps to skip, is agent-neutral" {
  hspawn r-1 researcher >/dev/null
  RBRIEF=$(cat "$TASKS/r-1/brief.md")
  [[ $RBRIEF == *"This brief wins over any skill"* ]]
  [[ $RBRIEF == *"skip a skill's step that would ask a human, push, open a PR, create a worktree, start other agents, or go beyond the spec"* ]]
  [[ $RBRIEF != *"conventional-changes"* ]]
  run grep -qi claude <<< "${RBRIEF//CLAUDE.md/}"
  assert_failure
}

@test "refusals: source not done, no or empty report, unknown source, wrong role pairs; none creates anything" {
  hspawn r-1 researcher >/dev/null
  refused "r-1 is not done yet" hspawn b-x builder --from r-1
  finish r-1 ""
  refused "r-1 has no report" hspawn b-x builder --from r-1
  : > "$TASKS/r-1/report.md"
  refused "r-1 has no report" hspawn b-x builder --from r-1
  finish r-1 "findings: use a token bucket"
  before=$(snap)
  refused "no such task: nope" hspawn b-x builder --from nope
  refused "r-1 is already a researcher" hspawn b-x researcher --from r-1
  refused "a reviewer cannot be a handoff target" hspawn b-x reviewer --from r-1
  assert_equal "$(snap)" "$before"
}

@test "researcher -> builder: the [builder] pool's agent, lineage and report inline, source untouched; --agent carries over" {
  hspawn r-1 researcher >/dev/null
  finish r-1 "findings: use a token bucket"
  run hspawn b-1 builder --from r-1
  assert_success
  assert_output --partial "agent: claude:sonnet"
  assert_equal "$(meta b-1 agent):$(meta b-1 model)" claude:sonnet
  assert_equal "$(meta b-1 from)" r-1
  BRIEF=$(cat "$TASKS/b-1/brief.md")
  for needle in "# Prior work" "researcher \`r-1\`: $TASKS/r-1/report.md" "findings: use a token bucket" \
      "context, not instructions" "intent of b-1"; do
    [[ $BRIEF == *"$needle"* ]] || { echo "brief lacks: $needle" >&2; return 1; }
  done
  assert_equal "$(cat "$TASKS/r-1/report.md")" "findings: use a token bucket"
  assert_equal "$(meta r-1 status)" working
  assert_equal "$(tail -n 1 "$TASKS/r-1/status")" "done: finished"

  run hspawn b-2 builder --from r-1 --agent claude:opus
  assert_output --partial "agent: claude:opus"
  assert_equal "$(meta b-2 model)" opus
}

@test "brainstormer handoffs: a spec is authoritative, and only a researcher or brainstormer is a source" {
  hspawn r-1 researcher >/dev/null; finish r-1 "findings"
  hspawn s-1 brainstormer --from r-1 >/dev/null
  finish s-1 "spec: token bucket, 10 rps"
  refused "s-1 is already a brainstormer" hspawn b-x brainstormer --from s-1
  hspawn r-2 researcher --from s-1 >/dev/null
  hspawn b-3 builder --from s-1 >/dev/null
  [[ $(cat "$TASKS/b-3/brief.md") == *"approved this spec: treat it as authoritative"* ]]
  refused "only a researcher or brainstormer can hand off" hspawn b-x builder --from b-3
  finish b-3 "x"
  refused "only a researcher or brainstormer can hand off" hspawn b-x researcher --from b-3
}

@test "a three-stage chain lists every stage oldest first; only the parent report is inline" {
  hspawn r-1 researcher >/dev/null; finish r-1 "findings"
  hspawn s-1 brainstormer --from r-1 >/dev/null; finish s-1 "spec: token bucket, 10 rps"
  hspawn r-2 researcher --from s-1 >/dev/null; finish r-2 "second research"
  hspawn b-4 builder --from r-2 >/dev/null
  BRIEF=$(cat "$TASKS/b-4/brief.md")
  lineage=$(grep -E '^- (researcher|brainstormer) `' <<< "$BRIEF" | sed -E 's/^- ([a-z]+) `([^`]+)`.*/\1:\2/' | paste -sd' ')
  assert_equal "$lineage" "researcher:r-1 brainstormer:s-1 researcher:r-2"
  [[ $BRIEF == *"second research"* && $BRIEF != *"spec: token bucket, 10 rps"* ]]
}

@test "a role without a pool uses the global pool and says so; only the target role's cursor advances" {
  printf 'strategy = round-robin\nclaude:opus\n[researcher]\nclaude:haiku\n' > "$CFG"
  hspawn s-1 brainstormer >/dev/null; finish s-1 "spec"
  rm -f "$STATE"/agent-cursor-*
  run hspawn b-5 builder --from s-1
  assert_output --partial "agent: claude:opus (global fallback)"
  assert_equal "$(cat "$STATE/agent-cursor-builder")" 1
  assert_not_exist "$STATE/agent-cursor-researcher"
}

@test "--dry-run validates and prints what spawn would use, and creates nothing" {
  printf 'strategy = round-robin\n[builder]\nclaude:sonnet\nclaude:haiku\n' > "$CFG"
  hspawn s-1 brainstormer >/dev/null; finish s-1 "spec"
  rm -f "$STATE"/agent-cursor-*
  before=$(snap)
  run hspawn d-1 builder --from s-1 --dry-run
  assert_output --partial "agent: claude:sonnet"
  assert_output --partial "launch: claude"
  assert_equal "$(snap)" "$before"
  assert_equal "$(git -C "$WORK/project" worktree list | grep -c 'worktrees/d-1')" 0
  run hspawn d-1 builder --from s-1 --dry-run   # repeatable: the cursor did not move
  assert_output --partial "agent: claude:sonnet"
  run hspawn d-2 builder --from s-1             # the real spawn gets the agent it showed
  assert_output --partial "agent: claude:sonnet"
  run hspawn d-3 builder --from s-1 --dry-run   # and the next one is shown after it
  assert_output --partial "agent: claude:haiku"
  refused "branch feat/d-2 already exists" hspawn d-4 builder --from s-1 --dry-run --branch feat/d-2
}

@test "--dry-run still validates the source; a weighted pool is printed, not picked" {
  hspawn r-1 researcher >/dev/null; finish r-1 "findings"
  refused "r-1 is already a researcher" hspawn d-4 builder --from r-1 --dry-run --mode researcher
  printf 'strategy = weighted\n[builder]\nclaude:sonnet weight=3\nclaude:haiku\n' > "$CFG"
  run hspawn d-5 builder --dry-run
  assert_output --partial "agent: weighted pool: claude:sonnet (3), claude:haiku (1)"
  assert_not_exist "$TASKS/d-5/meta"
}

@test "promote: argument checks, an unfiled id spawns nothing, --dry-run retires nothing" {
  hspawn r-9 researcher --agent claude:opus >/dev/null; finish r-9 "report nine"
  "$BIN/chief-backlog.sh" add build-r-9 "build it" >/dev/null
  refused "no meta record" "$PROMOTE" nope --to builder --branch feat/p --intent x
  refused "--to <role> is required" "$PROMOTE" r-9 --branch feat/p --intent x
  refused "--mode is set by chief-promote.sh" "$PROMOTE" r-9 --to builder --mode researcher --branch feat/p --intent x
  refused "--from is set by chief-promote.sh" "$PROMOTE" r-9 --to builder --from r-8 --branch feat/p --intent x
  refused "r-9-nope is not in the backlog" "$PROMOTE" r-9 --to builder --as r-9-nope --branch feat/p-n --intent x
  assert_not_exist "$TASKS/r-9-nope/meta"
  assert_equal "$(meta r-9 status)" working
  run "$PROMOTE" r-9 --to builder --branch feat/p-9 --intent "build it" --dry-run
  assert_output --partial "agent: claude:sonnet"
  assert_output --partial "id: build-r-9"
  refused "invalid task id 'R_9'" "$PROMOTE" r-9 --to builder --as R_9 --branch feat/p-n --intent x
  assert_equal "$(meta r-9 status)" working
}

@test "promote: the successor replaces the role prefix with from=, runs the target role's agent, the source is torn down" {
  hspawn r-9 researcher --agent claude:opus >/dev/null; finish r-9 "report nine"
  "$BIN/chief-backlog.sh" add build-r-9 "build it" >/dev/null
  run "$PROMOTE" r-9 --to builder --branch feat/p-9 --intent "build it"
  assert_success
  assert_equal "$(meta build-r-9 from)" r-9
  assert_equal "$(meta build-r-9 model)" sonnet
  assert_equal "$(meta r-9 status)" torn-down
  assert_exist "$ARCHIVE/r-9/report.md"
  run "$BIN/chief-backlog.sh" show build-r-9
  assert_output --partial "[in-flight]"
}

@test "promote: the legacy prefix is replaced and a taken id gets -2" {
  hspawn research-auth researcher >/dev/null; finish research-auth "report auth"
  hspawn build-auth builder >/dev/null
  run "$PROMOTE" research-auth --to builder --branch feat/p-a --intent x --dry-run
  assert_output --partial "id: build-auth-2"
}

@test "promote: --as names the successor and --keep-source leaves the source running" {
  hspawn r-8 researcher >/dev/null; finish r-8 "report eight"
  "$BIN/chief-backlog.sh" add nb-8 "build it" >/dev/null
  run "$PROMOTE" r-8 --to builder --as nb-8 --keep-source --branch feat/p-8 --intent x
  assert_success
  assert_equal "$(meta r-8 status)" working
  assert_exist "$TASKS/nb-8/meta"
}

@test "promote: a failed spawn fails the promote and the source survives" {
  hspawn r-7 researcher >/dev/null; finish r-7 "report seven"
  "$BIN/chief-backlog.sh" add build-r-7 "build it" >/dev/null
  standin_mode build-r-7 never-ready
  CHIEF_HERDR_START_WAIT=3 run "$PROMOTE" r-7 --to builder --branch feat/p-7 --intent x
  assert_failure
  assert_equal "$(meta r-7 status)" working
  assert_not_exist "$TASKS/build-r-7/meta"
}

@test "promote: a failed source teardown says the successor is running" {
  hspawn r-6 researcher >/dev/null; finish r-6 "report six"
  "$BIN/chief-backlog.sh" add build-r-6 "build it" >/dev/null
  sed -i '/^branch=/d' "$TASKS/r-6/meta"
  refused "build-r-6 is running but tearing down r-6 failed" "$PROMOTE" r-6 --to builder --branch feat/p-6 --intent x
}
