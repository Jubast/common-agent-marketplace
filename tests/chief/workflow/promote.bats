# chief-promote.sh: turns a finished researcher or brainstormer into its
# successor with chief-spawn.sh --from, on a real herdr.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  chief_herdr_server
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
  mkdir -p "$CHIEF_HOME/config"
  printf 'claude:opus\n[researcher]\nclaude:opus\n[brainstormer]\nclaude:opus\n[builder]\nclaude:sonnet\n' > "$CHIEF_HOME/config/agents"
}

teardown() { chief_herdr_stop; }

promote() { timeout 90 "$BIN/task/chief-promote.sh" "$@"; }
# done_researcher <id> - a finished researcher with a backlog item for its successor
done_researcher() {
  chief_spawn "$1" researcher --agent claude:opus >/dev/null; chief_finish "$1" "report of $1"
}

@test "args: refuses an unknown task, a missing --to, and --mode or --from" {
  done_researcher r-9
  "$BIN/chief-backlog.sh" add build-r-9 "build it" >/dev/null
  chief_refused "no meta record" promote nope --to builder --branch feat/p --intent x
  chief_refused "--to <role> is required" promote r-9 --branch feat/p --intent x
  chief_refused "--mode is set by chief-promote.sh" promote r-9 --to builder --mode researcher --branch feat/p --intent x
  chief_refused "--from is set by chief-promote.sh" promote r-9 --to builder --from r-8 --branch feat/p --intent x
  assert_equal "$(chief_meta r-9 status)" working
}

@test "args: refuses a successor id that is not in the backlog and spawns nothing" {
  done_researcher r-9
  chief_refused "r-9-nope is not in the backlog" promote r-9 --to builder --as r-9-nope --branch feat/p-n --intent x
  assert_not_exist "$TASKS/r-9-nope/meta"
  assert_equal "$(chief_meta r-9 status)" working
}

@test "args: refuses an invalid --as id" {
  done_researcher r-9
  chief_refused "invalid task id 'R_9'" promote r-9 --to builder --as R_9 --branch feat/p-n --intent x
  assert_equal "$(chief_meta r-9 status)" working
}

@test "dry-run: prints the successor's agent and id and retires nothing" {
  done_researcher r-9
  "$BIN/chief-backlog.sh" add build-r-9 "build it" >/dev/null
  run promote r-9 --to builder --branch feat/p-9 --intent "build it" --dry-run
  assert_output --partial "agent: claude:sonnet"
  assert_output --partial "id: build-r-9"
  assert_equal "$(chief_meta r-9 status)" working
}

@test "successor: replaces the role prefix, uses the target's agent, retires the source" {
  done_researcher r-9
  "$BIN/chief-backlog.sh" add build-r-9 "build it" >/dev/null
  run promote r-9 --to builder --branch feat/p-9 --intent "build it"
  assert_success
  assert_equal "$(chief_meta build-r-9 from)" r-9
  assert_equal "$(chief_meta build-r-9 model)" sonnet
  assert_equal "$(chief_meta r-9 status)" torn-down
  assert_exist "$ARCHIVE/r-9/report.md"
  run "$BIN/chief-backlog.sh" show build-r-9
  assert_output --partial "[in-flight]"
}

@test "successor: a legacy prefix is replaced and a taken id gets -2" {
  chief_spawn research-auth researcher >/dev/null; chief_finish research-auth "report auth"
  chief_spawn build-auth builder >/dev/null
  run promote research-auth --to builder --branch feat/p-a --intent x --dry-run
  assert_output --partial "id: build-auth-2"
}

@test "--as: names the successor and --keep-source leaves the source running" {
  chief_spawn r-8 researcher >/dev/null; chief_finish r-8 "report eight"
  "$BIN/chief-backlog.sh" add nb-8 "build it" >/dev/null
  run promote r-8 --to builder --as nb-8 --keep-source --branch feat/p-8 --intent x
  assert_success
  assert_equal "$(chief_meta r-8 status)" working
  assert_exist "$TASKS/nb-8/meta"
}

@test "failure: a failed spawn fails the promote and the source survives" {
  chief_spawn r-7 researcher >/dev/null; chief_finish r-7 "report seven"
  "$BIN/chief-backlog.sh" add build-r-7 "build it" >/dev/null
  standin_never_ready build-r-7
  CHIEF_HERDR_START_WAIT=3 run promote r-7 --to builder --branch feat/p-7 --intent x
  assert_failure 1
  assert_equal "$(chief_meta r-7 status)" working
  assert_not_exist "$TASKS/build-r-7/meta"
}

@test "failure: a failed source teardown says the successor is running" {
  chief_spawn r-6 researcher >/dev/null; chief_finish r-6 "report six"
  "$BIN/chief-backlog.sh" add build-r-6 "build it" >/dev/null
  sed -i '/^branch=/d' "$TASKS/r-6/meta"
  chief_refused "build-r-6 is running but tearing down r-6 failed" promote r-6 --to builder --branch feat/p-6 --intent x
}
