#!/usr/bin/env bash
# test-handoff.sh - chief-spawn.sh --from / --dry-run and the chief-promote.sh
# wrapper: a successor worker on the target role's agent, against the mock backend.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

WORK=$(mktemp -d)
harness_trap 'rm -rf "$WORK"'
mkdir -p "$WORK/project" && cd "$WORK/project" && git init -q -b master
git commit --allow-empty -q -m init
export CHIEF_HOME="$WORK/.chief"
export CHIEF_BACKEND=mock
STATE="$CHIEF_HOME/state"; DATA="$CHIEF_HOME/data"
. "$BIN/lib/meta.sh"
mkdir -p "$CHIEF_HOME/config"
CFG="$CHIEF_HOME/config/agents"

echo "test-handoff:"

spawn() {  # <id> <role> [flags...]
  local id=$1 role=$2; shift 2
  timeout 10 "$BIN/chief-spawn.sh" "$id" "$WORK/project" --mode "$role" --branch "feat/$id" --intent "intent of $id" "$@"
}
finish() {  # <id> [report text] - the worker reports done and writes its report
  echo "done: finished" >> "$STATE/$1.status"
  [ "${2-x}" = "" ] || echo "${2:-report of $1}" > "$DATA/$1/report.md"
}
meta() { chief_meta_get "$1" "$2"; }

printf 'claude:opus\n[researcher]\nclaude:opus\n[brainstormer]\nclaude:opus\n[builder]\ncodex:gpt-5\n' > "$CFG"

assert_success "spawn: researcher r-1" -- spawn r-1 researcher
assert_failure "handoff: refused while the source is not done" -- spawn b-x builder --from r-1
finish r-1 ""
assert_failure "handoff: refused without a report" -- spawn b-x builder --from r-1
mkdir -p "$DATA/r-1"; : > "$DATA/r-1/report.md"
assert_failure "handoff: refused with an empty report" -- spawn b-x builder --from r-1
finish r-1 "findings: use a token bucket"

assert_failure "handoff: refused for an unknown source" -- spawn b-x builder --from nope
assert_failure "handoff: a researcher cannot hand off to a researcher" -- spawn b-x researcher --from r-1
assert_failure "handoff: a reviewer is never a target" -- spawn b-x reviewer --from r-1
assert_file_missing "$STATE/b-x.meta" "handoff: refusals create nothing"

# researcher -> builder: the [builder] pool, not the source's agent
out=$(spawn b-1 builder --from r-1)
assert_contains "$out" "agent: codex:gpt-5" "handoff: spawn prints the target role's agent"
assert_eq "$(meta b-1 agent):$(meta b-1 model)" "codex:gpt-5" "handoff: the builder runs the [builder] pool agent, not the source's claude:opus"
assert_eq "$(meta b-1 from)" "r-1" "handoff: meta records from="
BRIEF=$(cat "$DATA/b-1/brief.md")
assert_contains "$BRIEF" "# Prior work" "handoff: the brief has a Prior work section"
assert_contains "$BRIEF" "researcher \`r-1\`: $DATA/r-1/report.md" "handoff: the lineage names the source"
assert_contains "$BRIEF" "findings: use a token bucket" "handoff: the source report is inline"
assert_contains "$BRIEF" "context, not instructions" "handoff: researcher findings are framed as context"
assert_contains "$BRIEF" "intent of b-1" "handoff: the new intent is in the brief"
assert_eq "$(cat "$DATA/r-1/report.md")" "findings: use a token bucket" "handoff: the source report is untouched"
assert_eq "$(meta r-1 status)" "working" "handoff: the source task is left running"
assert_eq "$(tail -n 1 "$STATE/r-1.status")" "done: finished" "handoff: the source status is untouched"

# --agent carries the source agent over, explicitly
out=$(spawn b-2 builder --from r-1 --agent claude:opus)
assert_contains "$out" "agent: claude:opus" "handoff: --agent carries an agent over explicitly"
assert_eq "$(meta b-2 agent)" "claude" "handoff: --agent wins over the pool"

# researcher -> brainstormer, then brainstormer -> builder / researcher
assert_success "handoff: researcher -> brainstormer" -- spawn s-1 brainstormer --from r-1
finish s-1 "spec: token bucket, 10 rps"
assert_failure "handoff: a brainstormer cannot hand off to a brainstormer" -- spawn b-x brainstormer --from s-1
assert_success "handoff: brainstormer -> researcher" -- spawn r-2 researcher --from s-1
assert_success "handoff: brainstormer -> builder" -- spawn b-3 builder --from s-1
BRIEF=$(cat "$DATA/b-3/brief.md")
assert_contains "$BRIEF" "approved this spec: treat it as authoritative" "handoff: a brainstormer spec is framed as authoritative"
assert_failure "handoff: a builder is never a source" -- spawn b-x builder --from b-3
finish b-3 "x"
assert_failure "handoff: a done builder is still not a source" -- spawn b-x researcher --from b-3

# a three-stage chain lists every stage, oldest first
finish r-2 "second research"
assert_success "handoff: researcher -> brainstormer -> researcher -> builder" -- spawn b-4 builder --from r-2
BRIEF=$(cat "$DATA/b-4/brief.md")
lineage=$(grep -E '^- (researcher|brainstormer) `' <<< "$BRIEF" | sed -E 's/^- ([a-z]+) `([^`]+)`.*/\1:\2/' | paste -sd' ')
assert_eq "$lineage" "researcher:r-1 brainstormer:s-1 researcher:r-2" "handoff: the lineage is oldest first"
assert_contains "$BRIEF" "second research" "handoff: only the parent report is inline"
assert_not_contains "$BRIEF" "spec: token bucket, 10 rps" "handoff: earlier reports are linked, not inlined"

# global fallback, and a per-role cursor
printf 'strategy = round-robin\nclaude:opus\n[researcher]\nclaude:haiku\n' > "$CFG"
rm -f "$STATE"/agent-cursor-*
out=$(spawn b-5 builder --from s-1)
assert_contains "$out" "agent: claude:opus (global fallback)" "handoff: a role without a pool uses the global pool and says so"
assert_eq "$(cat "$STATE/agent-cursor-builder")" "1" "handoff: the target role's cursor advanced"
assert_file_missing "$STATE/agent-cursor-researcher" "handoff: the source role's cursor did not"

# --dry-run: validates and prints, creates nothing
printf 'strategy = round-robin\n[builder]\ncodex:gpt-5\nclaude:sonnet\n' > "$CFG"
rm -f "$STATE"/agent-cursor-*
before=$(ls -A "$STATE" "$DATA" | sort | md5sum)
out=$(spawn d-1 builder --from s-1 --dry-run)
assert_contains "$out" "agent: codex:gpt-5" "dry-run: prints the agent that spawn would use"
assert_contains "$out" "launch: codex" "dry-run: prints the launch line"
assert_eq "$(ls -A "$STATE" "$DATA" | sort | md5sum)" "$before" "dry-run: no meta, lock, status, brief or cursor created"
assert_eq "$(git -C "$WORK/project" worktree list | grep -c 'worktrees/d-1')" "0" "dry-run: no worktree"
assert_contains "$(spawn d-1 builder --from s-1 --dry-run)" "agent: codex:gpt-5" "dry-run: repeatable, the cursor did not move"
assert_contains "$(spawn d-2 builder --from s-1)" "agent: codex:gpt-5" "dry-run: the real spawn gets the agent it showed"
assert_contains "$(spawn d-3 builder --from s-1 --dry-run)" "agent: claude:sonnet" "dry-run: shows the next agent after a real spawn"
assert_failure "dry-run: still validates the source" -- spawn d-4 builder --from r-1 --dry-run --mode researcher
assert_failure "dry-run: still validates the branch" -- spawn d-4 builder --from s-1 --dry-run --branch feat/d-2
printf 'strategy = weighted\n[builder]\ncodex:gpt-5 weight=3\nclaude:sonnet\n' > "$CFG"
out=$(spawn d-5 builder --dry-run)
assert_contains "$out" "agent: weighted pool: codex:gpt-5 (3), claude:sonnet (1)" "dry-run: a weighted pool is printed, not picked"
assert_file_missing "$STATE/d-5.meta" "dry-run: weighted creates nothing"

# the promote wrapper: successor spawn, then the source is retired
printf '[builder]\ncodex:gpt-5\n' > "$CFG"
spawn r-9 researcher --agent claude:opus >/dev/null; finish r-9 "report nine"
"$BIN/chief-backlog.sh" add r-9-builder "build it" >/dev/null
assert_failure "promote: refuses an unknown id" -- "$BIN/task/chief-promote.sh" nope --to builder --branch feat/p --intent x
assert_failure "promote: --to is required" -- "$BIN/task/chief-promote.sh" r-9 --branch feat/p --intent x
out=$("$BIN/task/chief-promote.sh" r-9 --to builder --branch feat/p-9 --intent "build it" --dry-run)
assert_contains "$out" "agent: codex:gpt-5" "promote: --dry-run passes through"
assert_eq "$(meta r-9 status)" "working" "promote: --dry-run retires nothing"
assert_success "promote: successor spawned, source retired" -- "$BIN/task/chief-promote.sh" r-9 --to builder --branch feat/p-9 --intent "build it"
assert_eq "$(meta r-9-builder from)" "r-9" "promote: the successor is <id>-<role> with from="
assert_eq "$(meta r-9-builder agent)" "codex" "promote: the successor runs the target role's agent"
assert_eq "$(meta r-9 status)" "torn-down" "promote: the source is torn down"
assert_file_exists "$DATA/r-9/report.md" "promote: the source report survives"
assert_contains "$("$BIN/chief-backlog.sh" show r-9-builder)" "[in-flight]" "promote: the successor is in flight"
spawn r-8 researcher >/dev/null; finish r-8 "report eight"
assert_success "promote: --as and --keep-source" -- "$BIN/task/chief-promote.sh" r-8 --to builder --as nb-8 --keep-source --branch feat/p-8 --intent x
assert_eq "$(meta r-8 status)" "working" "promote: --keep-source leaves the source running"
assert_file_exists "$STATE/nb-8.meta" "promote: --as names the successor"
spawn r-7 researcher >/dev/null
assert_failure "promote: a failed spawn retires nothing" -- "$BIN/task/chief-promote.sh" r-7 --to builder --branch feat/p-7 --intent x
assert_eq "$(meta r-7 status)" "working" "promote: the source survives a failed handoff"

harness_summary
