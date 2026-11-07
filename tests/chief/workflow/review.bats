# chief-review.sh on a real herdr: the gates, round 1 (a linked reviewer with
# the pinned spec) and round 2 (the same reviewer re-armed), plus how the
# builder/reviewer link shows in crew-state, the digest and the watcher.
# Strategy `all` is in review-all.bats; the teardown cascade in teardown.bats.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  chief_herdr_server
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
  RV="$BIN/task/chief-review.sh"
  CS="$BIN/task/chief-crew-state.sh"
  BL="$BIN/chief-backlog.sh"
}

teardown() { chief_herdr_stop; }

# round_one <id> - a done builder with its round 1 reviewer started
round_one() {
  chief_done_builder "$1" hello.txt
  SHA1=$(git -C "$CHIEF_HOME/worktrees/$1" rev-parse HEAD)
  chief_review "$1" >/dev/null
}
# round_two <id> - round 1 failed and was reported, the builder fixed it, round 2 requested
round_two() {
  round_one "$1"
  printf 'Verdict: FAIL\n' > "$TASKS/$1-rv/report.md"
  echo "done: round 1 FAIL (1 blocking) @x" >> "$TASKS/$1-rv/status"
  "$BL" hold "$1-rv" "round 1 FAIL, idle" >/dev/null
  "$BL" hold "$1" "reported" >/dev/null
  SHA2=$(chief_commit_file "$1" more.txt)
  "$BL" status "$1" in-flight >/dev/null
  echo "working: resuming" >> "$TASKS/$1/status"
  echo "done: ${SHA2:0:7} fixed" >> "$TASKS/$1/status"
  chief_review "$1" >/dev/null
}

@test "gates: refuse until the builder is done, committed, pinned to HEAD and clean" {
  "$BL" add b-1 "Add hello" >/dev/null
  chief_spawn_quiet b-1 --intent "Add hello"
  run "$RV" nope
  assert_failure 1
  run chief_review b-1; assert_output --partial "is not done"
  echo "done: x" >> "$TASKS/b-1/status"
  run chief_review b-1; assert_output --partial "no commit ahead of main"
  SHA1=$(chief_commit_file b-1 hello.txt)
  run chief_review b-1; assert_output --partial "does not start with HEAD's SHA"
  echo "done: ${SHA1:0:7} added hello.txt" >> "$TASKS/b-1/status"
  SHAX=$(chief_commit_file b-1 late.txt)
  run chief_review b-1; assert_output --partial "does not start with HEAD's SHA ${SHAX:0:7}"
  git -C "$CHIEF_HOME/worktrees/b-1" reset -q --hard "$SHA1"
  echo dirt > "$CHIEF_HOME/worktrees/b-1/dirt.txt"
  run chief_review b-1; assert_output --partial "not clean"
  assert_not_exist "$TASKS/b-1-rv/meta"
}

@test "round 1: spawns a reviewer linked both ways" {
  chief_done_builder b-1 hello.txt
  run chief_review b-1
  assert_output --partial "review: b-1-rv round 1 of b-1 @$(git -C "$CHIEF_HOME/worktrees/b-1" rev-parse --short HEAD)"
  assert_equal "$(chief_meta_get b-1-rv mode)" reviewer
  assert_equal "$(chief_meta_get b-1-rv branch)" chore/b-1-rv
  assert_equal "$(chief_meta_get b-1-rv for)" b-1
  assert_equal "$(chief_meta_get b-1 reviewer)" b-1-rv
  assert_equal "$(chief_meta_get b-1 review_round)" 1
  run "$BL" show b-1-rv
  assert_output --partial "[in-flight] review of b-1: T b-1"
}

@test "round 1: the reviewer's brief pins the SHA, base, branch and done line" {
  round_one b-1
  assert_contains_all "$(cat "$TASKS/b-1-rv/brief.md")" "Pinned SHA: $SHA1" "Base: main" "Branch: feat/b-1" "$TASKS/b-1/brief.md" \
    "Builder done line: ${SHA1:0:7} ok" "Review round 1"
}

@test "round 1: the reviewer's brief points at the builder's DoD evidence" {
  round_one b-1
  assert_contains_all "$(cat "$TASKS/b-1-rv/brief.md")" "Builder DoD evidence: $TASKS/b-1/report.md"
}

@test "round 1: crew-state and the session digest show the link" {
  round_one b-1
  run "$CS" b-1-rv; assert_output --partial "[for: b-1]"
  run "$CS" b-1; assert_output --partial "[reviewer: b-1-rv]"
  digest=$(cd "$WORK/project" && "$REPO_ROOT/plugins/chief/hooks/session-start.sh" | jq -r .hookSpecificOutput.additionalContext)
  assert_contains_all "$digest" "[mode: reviewer] [agent: claude] [for: b-1]"
}

@test "round 1: refuses the same SHA while the reviewer works" {
  round_one b-1
  chief_reviewer_working b-1-rv
  run chief_review b-1
  assert_output --partial "already reviewing ${SHA1:0:7}"
}

@test "round 2: refuses a builder that has not reported done again" {
  round_one b-1
  printf 'Verdict: FAIL\n' > "$TASKS/b-1-rv/report.md"
  echo "done: round 1 FAIL (1 blocking) @x" >> "$TASKS/b-1-rv/status"
  chief_commit_file b-1 more.txt >/dev/null
  echo "working: resuming" >> "$TASKS/b-1/status"
  run chief_review b-1; assert_output --partial "is not done"
}

@test "round 2: re-arms the reviewer with the new SHA in its inbox" {
  round_two b-1
  assert_equal "$(cat "$TASKS/b-1-rv/report.round-1.md")" "Verdict: FAIL"
  assert_not_exist "$TASKS/b-1-rv/report.md"
  assert_contains_all "$(cat "$TASKS/b-1-rv/inbox/001.msg")" "Review round 2" "Pinned SHA: $SHA2" "$TASKS/b-1-rv/report.round-1.md"
  assert_equal "$(tail -n 1 "$TASKS/b-1-rv/status")" "working: round 2 requested"
}

@test "round 2: the reviewer and its backlog record are back in flight" {
  round_two b-1
  run "$CS" b-1-rv; assert_output --partial "state: working"
  run "$BL" show b-1-rv; assert_output --partial "[in-flight]"
  assert_equal "$(chief_meta_get b-1-rv status)" working
  assert_equal "$(chief_meta_get b-1 review_round)" 2
}

@test "round 2: refuses the same SHA again without a second message" {
  round_two b-1
  run chief_review b-1; assert_output --partial "already reviewing ${SHA2:0:7}"
  assert_equal "$(ls "$TASKS/b-1-rv/inbox" | grep -c msg)" 1
}

@test "watch: the re-armed reviewer's working line does not wake Chief" {
  round_two b-1
  chief_wait_settled b-1-rv
  "$BL" hold b-1 "reported" >/dev/null
  chief_watch_silent
}

@test "watch: a done that differs from the baseline wakes Chief" {
  round_two b-1
  chief_wait_settled b-1-rv
  "$BL" hold b-1 "reported" >/dev/null
  echo "done: round 2 PASS @${SHA2:0:7}" >> "$TASKS/b-1-rv/status"
  chief_watch_once
  assert_output --partial "b-1-rv: state: done · round 2 PASS @${SHA2:0:7}"
}

@test "watch: a done identical to the baseline stays quiet" {
  round_two b-1
  chief_wait_settled b-1-rv
  "$BL" hold b-1 "reported" >/dev/null
  echo "done: round 2 PASS @${SHA2:0:7}" >> "$TASKS/b-1-rv/status"
  chief_watch_once
  "$BL" hold b-1-rv "round 2 PASS, idle" >/dev/null
  "$BL" status b-1-rv in-flight >/dev/null
  chief_watch_silent
}

@test "gates: refuses a round for a builder whose reviewer was torn down" {
  round_one b-2
  timeout 90 "$BIN/chief-teardown.sh" b-2-rv >/dev/null
  run chief_review b-2
  assert_output --partial "reviewer b-2-rv was torn down"
}

@test "long id: the reviewer id is fitted, reused after a failure, found in round 2" {
  LB=build-keycloak-name-extra-words
  "$BL" add $LB "Long" >/dev/null
  chief_spawn_quiet $LB --branch feat/long --intent "Long"
  chief_commit_file $LB long.txt >/dev/null
  echo "done: $(git -C "$CHIEF_HOME/worktrees/$LB" rev-parse --short HEAD) ok" >> "$TASKS/$LB/status"
  standin_never_ready build-keycloak-name-extra-rv
  CHIEF_HERDR_START_WAIT=3 run "$RV" $LB
  assert_failure 1
  assert_not_exist "$TASKS/build-keycloak-name-extra-rv/meta"
  rm "$STANDIN_DIR/modes/build-keycloak-name-extra-rv"
  chief_review $LB >/dev/null
  assert_equal "$(chief_meta_get $LB reviewer)" build-keycloak-name-extra-rv
  chief_commit_file $LB long2.txt >/dev/null
  echo "done: $(git -C "$CHIEF_HOME/worktrees/$LB" rev-parse --short HEAD) ok" >> "$TASKS/$LB/status"
  run chief_review $LB
  assert_output --partial "review: build-keycloak-name-extra-rv round 2 of $LB"
}

@test "manual: a reviewer spawned by hand on an arbitrary branch has no builder link" {
  git -C "$WORK/project" branch feat/other main
  chief_spawn_quiet rv-1 --mode reviewer --branch chore/rv-1 --intent "Review feat/other" --spec "Branch: feat/other"
  run cat "$TASKS/rv-1/brief.md"
  assert_output --partial "Branch: feat/other"
  run "$CS" rv-1
  assert_output --partial "[mode: reviewer]"
  refute_output --partial "[for:"
}
