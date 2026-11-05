# chief-review.sh (rounds, gates, links), the reviewer brief and lifecycle, the
# teardown cascade and the builder/reviewer link in crew-state and watch, on a
# real herdr.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
  RV="$BIN/task/chief-review.sh"
  CS="$BIN/task/chief-crew-state.sh"
  BL="$BIN/chief-backlog.sh"
  TEMPLATES="$REPO_ROOT/plugins/chief/templates"
  git -C "$WORK/project" branch -m master main
}

teardown() { chief_herdr_stop; }

commit() {  # <id> <file>: commit a file in the builder's worktree, print the sha
  ( cd "$CHIEF_HOME/worktrees/$1" && echo "$2" > "$2" && git add "$2" \
    && git commit -q -m "add $2" && git rev-parse HEAD )
}
newb() {  # <id> [file]: a spawned builder with one commit and a done line carrying its sha
  "$BL" add "$1" "T $1" >/dev/null
  timeout 90 "$BIN/chief-spawn.sh" "$1" "$WORK/project" --mode builder --branch "feat/$1" --intent "T $1" >/dev/null
  commit "$1" "${2:-$1.txt}" >/dev/null
  echo "done: $(git -C "$CHIEF_HOME/worktrees/$1" rev-parse --short HEAD) ok" >> "$TASKS/$1/status"
}
review() { timeout 90 "$RV" "$@" 2>&1; }
rwork() { echo "working: reviewing" >> "$TASKS/$1/status"; touch "$TASKS/$1/turn-ended"; }  # a reviewer mid-review
rdone() { echo "done: round $2 PASS @x" >> "$TASKS/$1/status"; }  # <reviewer> <round>

@test "gates: unknown task, not done, no commit, no sha, late commit, dirty worktree; nothing is spawned" {
  "$BL" add b-1 "Add hello" >/dev/null
  timeout 90 "$BIN/chief-spawn.sh" b-1 "$WORK/project" --mode builder --branch feat/b-1 --intent "Add hello" >/dev/null
  run "$RV" nope
  assert_failure
  run review b-1; assert_output --partial "is not done"
  echo "done: x" >> "$TASKS/b-1/status"
  run review b-1; assert_output --partial "no commit ahead of main"
  SHA1=$(commit b-1 hello.txt)
  run review b-1; assert_output --partial "does not start with HEAD's SHA"
  echo "done: ${SHA1:0:7} added hello.txt" >> "$TASKS/b-1/status"
  SHAX=$(commit b-1 late.txt)
  run review b-1; assert_output --partial "does not start with HEAD's SHA ${SHAX:0:7}"
  git -C "$CHIEF_HOME/worktrees/b-1" reset -q --hard "$SHA1"
  echo dirt > "$CHIEF_HOME/worktrees/b-1/dirt.txt"
  run review b-1; assert_output --partial "not clean"
  assert_not_exist "$TASKS/b-1-rv/meta"
}

@test "round 1 spawns a linked reviewer with the pinned spec; the same SHA is refused while it works" {
  newb b-1 hello.txt
  SHA1=$(git -C "$CHIEF_HOME/worktrees/b-1" rev-parse HEAD)
  echo "done: ${SHA1:0:7} added hello.txt" >> "$TASKS/b-1/status"
  run review b-1
  assert_output --partial "review: b-1-rv round 1 of b-1 @${SHA1:0:7}"
  assert_equal "$(chief_meta_get b-1-rv mode)" reviewer
  assert_equal "$(chief_meta_get b-1-rv branch)" chore/b-1-rv
  assert_equal "$(chief_meta_get b-1-rv for)" b-1
  assert_equal "$(chief_meta_get b-1 reviewer)" b-1-rv
  assert_equal "$(chief_meta_get b-1 review_round)" 1
  run "$BL" show b-1-rv
  assert_output --partial "[in-flight] review of b-1: T b-1"
  BRIEF=$(cat "$TASKS/b-1-rv/brief.md")
  for needle in "Pinned SHA: $SHA1" "Base: main" "Branch: feat/b-1" "$TASKS/b-1/brief.md" \
      "Builder done line: ${SHA1:0:7} added hello.txt" "Review round 1"; do
    [[ $BRIEF == *"$needle"* ]] || { echo "spec lacks: $needle" >&2; return 1; }
  done
  run "$CS" b-1-rv; assert_output --partial "[for: b-1]"
  run "$CS" b-1; assert_output --partial "[reviewer: b-1-rv]"
  digest=$(cd "$WORK/project" && "$REPO_ROOT/plugins/chief/hooks/session-start.sh" | jq -r .hookSpecificOutput.additionalContext)
  [[ $digest == *"[mode: reviewer] [agent: claude] [for: b-1]"* ]]
  rwork b-1-rv
  run review b-1
  assert_output --partial "already reviewing ${SHA1:0:7}"
}

@test "round 2 re-arms the reviewer; the watcher wakes on a differing done and suppresses an identical one; teardown cascades" {
  newb b-1 hello.txt
  review b-1 >/dev/null
  printf 'Verdict: FAIL\n' > "$TASKS/b-1-rv/report.md"
  echo "done: round 1 FAIL (1 blocking) @x" >> "$TASKS/b-1-rv/status"
  "$BL" hold b-1-rv "round 1 FAIL, idle" >/dev/null
  "$BL" hold b-1 "reported" >/dev/null

  SHA2=$(commit b-1 more.txt)
  echo "working: resuming" >> "$TASKS/b-1/status"
  run review b-1; assert_output --partial "is not done"
  "$BL" status b-1 in-flight >/dev/null
  echo "done: ${SHA2:0:7} fixed" >> "$TASKS/b-1/status"
  run review b-1
  assert_output --partial "review: b-1-rv round 2 of b-1 @${SHA2:0:7}"
  assert_equal "$(cat "$TASKS/b-1-rv/report.round-1.md")" "Verdict: FAIL"
  assert_not_exist "$TASKS/b-1-rv/report.md"
  MSG=$(cat "$TASKS/b-1-rv/inbox/001.msg")
  for needle in "Review round 2" "Pinned SHA: $SHA2" "$TASKS/b-1-rv/report.round-1.md"; do
    [[ $MSG == *"$needle"* ]] || { echo "message lacks: $needle" >&2; return 1; }
  done
  assert_equal "$(tail -n 1 "$TASKS/b-1-rv/status")" "working: round 2 requested"
  run "$CS" b-1-rv; assert_output --partial "state: working"
  run "$BL" show b-1-rv; assert_output --partial "[in-flight]"
  assert_equal "$(chief_meta_get b-1-rv status)" working
  assert_equal "$(chief_meta_get b-1 review_round)" 2
  run review b-1; assert_output --partial "already reviewing ${SHA2:0:7}"
  assert_equal "$(ls "$TASKS/b-1-rv/inbox" | grep -c msg)" 1

  wait_settled b-1-rv
  "$BL" hold b-1 "reported" >/dev/null
  watch_silent   # the re-armed reviewer's working line does not wake Chief
  echo "done: round 2 PASS @${SHA2:0:7}" >> "$TASKS/b-1-rv/status"
  watch_once
  assert_output --partial "b-1-rv: state: done · round 2 PASS @${SHA2:0:7}"
  "$BL" hold b-1-rv "round 2 PASS, idle" >/dev/null
  "$BL" status b-1-rv in-flight >/dev/null
  watch_silent   # a done identical to the baseline is suppressed
  "$BL" hold b-1-rv "idle" >/dev/null

  run "$BIN/chief-teardown.sh" b-1
  assert_failure
  assert_exist "$CHIEF_HOME/worktrees/b-1-rv"
  git -C "$WORK/project" merge --ff-only feat/b-1 >/dev/null
  run "$BIN/chief-teardown.sh" b-1
  assert_output --partial "torn down: b-1 "
  assert_output --partial "torn down: b-1-rv "
  assert_not_exist "$CHIEF_HOME/worktrees/b-1-rv"
  assert_exist "$ARCHIVE/b-1-rv/report.round-1.md"
  run "$BL" show b-1-rv; assert_output --partial "[done]"
  run "$RV" b-1
  assert_failure
}

@test "a reviewer tears down alone; abandoning its builder does not tear it down twice" {
  newb b-2
  review b-2 >/dev/null
  run "$BIN/chief-teardown.sh" b-2-rv
  assert_output --partial "torn down: b-2-rv "
  assert_equal "$(git -C "$WORK/project" worktree list | grep -c 'worktrees/b-2 ')" 1
  run review b-2
  assert_output --partial "reviewer b-2-rv was torn down"
  run "$BIN/chief-teardown.sh" b-2 --abandon
  assert_equal "$(grep -c '^torn down' <<< "$output")" 1
}

@test "a reviewer whose worktree was removed by hand is still discarded with its builder" {
  newb b-3
  review b-3 >/dev/null
  git -C "$WORK/project" worktree remove --force "$CHIEF_HOME/worktrees/b-3-rv"
  run "$BIN/chief-teardown.sh" b-3 --abandon
  assert_output --partial "torn down: b-3-rv "
  assert_equal "$(chief_meta_get b-3-rv status)" torn-down
  run "$BL" show b-3-rv; assert_output --partial "[done]"
  assert_equal "$(git -C "$WORK/project" branch --list chore/b-3-rv)" ""
}

@test "a long builder id: the reviewer id is fitted, reused after a failed spawn and found again in round 2" {
  LB=build-keycloak-name-extra-words
  "$BL" add $LB "Long" >/dev/null
  timeout 90 "$BIN/chief-spawn.sh" $LB "$WORK/project" --mode builder --branch feat/long --intent "Long" >/dev/null
  commit $LB long.txt >/dev/null
  echo "done: $(git -C "$CHIEF_HOME/worktrees/$LB" rev-parse --short HEAD) ok" >> "$TASKS/$LB/status"
  standin_mode build-keycloak-name-extra-rv never-ready
  CHIEF_HERDR_START_WAIT=3 run "$RV" $LB
  assert_failure
  assert_not_exist "$TASKS/build-keycloak-name-extra-rv/meta"
  rm "$STANDIN_DIR/modes/build-keycloak-name-extra-rv"
  review $LB >/dev/null
  assert_equal "$(chief_meta_get $LB reviewer)" build-keycloak-name-extra-rv
  commit $LB long2.txt >/dev/null
  echo "done: $(git -C "$CHIEF_HOME/worktrees/$LB" rev-parse --short HEAD) ok" >> "$TASKS/$LB/status"
  run review $LB
  assert_output --partial "review: build-keycloak-name-extra-rv round 2 of $LB"
}

@test "strategy all: one reviewer per entry, one wake per round, failed and torn-down siblings, cascade" {
  mkdir -p "$CHIEF_HOME/config"
  printf '[reviewer]\nstrategy = all\nclaude:sonnet\nclaude:haiku\n' > "$CHIEF_HOME/config/agents"
  newb b-4
  run review b-4
  "$BL" hold b-4 reported >/dev/null
  assert_output --partial "review: b-4-rv-1, b-4-rv-2 round 1 of b-4"
  assert_equal "$(chief_meta_get b-4 reviewer)" "b-4-rv-1 b-4-rv-2"
  assert_equal "$(chief_meta_get b-4-rv-1 model):$(chief_meta_get b-4-rv-2 model)" "sonnet:haiku"
  assert_equal "$(chief_meta_get b-4-rv-2 for)" b-4
  rwork b-4-rv-1; rwork b-4-rv-2
  rdone b-4-rv-1 1
  watch_silent   # the first done stays quiet while a sibling works
  rdone b-4-rv-2 1
  watch_once
  assert_output --partial "b-4-rv-2: state: done"   # the last done wakes Chief
  watch_silent

  S4=$(commit b-4 b4b.txt); echo "done: ${S4:0:7} fixed" >> "$TASKS/b-4/status"
  run review b-4
  "$BL" hold b-4 reported >/dev/null
  assert_output --partial "review: b-4-rv-1, b-4-rv-2 round 2 of b-4"
  [[ $(cat "$TASKS/b-4-rv-2/inbox/001.msg") == *"Pinned SHA: $S4"* ]]
  wait_settled b-4-rv-1; wait_settled b-4-rv-2
  watch_silent
  rdone b-4-rv-1 2; rdone b-4-rv-2 2
  watch_once
  assert_output --partial "state: done · round 2"   # both done in the same poll: one wake
  watch_silent

  S4=$(commit b-4 b4c.txt); echo "done: ${S4:0:7} again" >> "$TASKS/b-4/status"
  review b-4 >/dev/null; "$BL" hold b-4 reported >/dev/null
  wait_settled b-4-rv-1; wait_settled b-4-rv-2
  echo "failed: could not run checks" >> "$TASKS/b-4-rv-1/status"
  watch_once
  assert_output --partial "b-4-rv-1: state: failed"   # a failed sibling wakes at once
  rdone b-4-rv-2 3
  watch_once
  assert_output --partial "b-4-rv-2: state: done"      # and does not hold the other back

  S4=$(commit b-4 b4d.txt); echo "done: ${S4:0:7} more" >> "$TASKS/b-4/status"
  review b-4 >/dev/null; "$BL" hold b-4 reported >/dev/null
  "$BIN/chief-teardown.sh" b-4-rv-1 --abandon >/dev/null 2>&1
  rdone b-4-rv-2 4
  watch_once
  assert_output --partial "b-4-rv-2: state: done"      # a torn-down sibling is skipped
  S4=$(commit b-4 b4e.txt); echo "done: ${S4:0:7} last" >> "$TASKS/b-4/status"
  run review b-4
  assert_output --partial "review: b-4-rv-2 round 5 of b-4"
  "$BL" hold b-4-rv-2 idle >/dev/null

  run "$BIN/chief-teardown.sh" b-4 --abandon
  assert_output --partial "torn down: b-4-rv-2 "
  assert_equal "$(grep -c '^torn down' <<< "$output")" 2
}

@test "strategy all: a spawn failure discards the reviewers already started and links nothing" {
  mkdir -p "$CHIEF_HOME/config"
  printf '[reviewer]\nstrategy = all\nclaude:sonnet\nclaude:haiku\n' > "$CHIEF_HOME/config/agents"
  newb b-6
  standin_mode b-6-rv-2 never-ready
  CHIEF_HERDR_START_WAIT=3 run "$RV" b-6
  assert_failure
  assert_equal "$(chief_meta_get b-6-rv-1 status):$(chief_meta_get b-6 reviewer 2>/dev/null || true)" "torn-down:"
}

@test "manual use on an arbitrary branch: a reviewer spawned with --spec has no builder link" {
  git -C "$WORK/project" branch feat/other main
  timeout 90 "$BIN/chief-spawn.sh" rv-1 "$WORK/project" --mode reviewer --branch chore/rv-1 --intent "Review feat/other" --spec "Branch: feat/other" >/dev/null
  run cat "$TASKS/rv-1/brief.md"
  assert_output --partial "Branch: feat/other"
  for ph in TASK SPEC BRANCH REPORT_FILE STATUS_FILE TURN_FILE INBOX_DIR; do refute_output --partial "{$ph}"; done
  run "$CS" rv-1
  assert_output --partial "[mode: reviewer]"
  refute_output --partial "[for:"
  run cat "$TASKS/rv-1/lifecycle"
  assert_output --partial "(reviewer)"
  refute_output --partial "{TASK_ID}"
}

@test "the reviewer brief carries the checklist, report format and read-only rules" {
  RB=$(cat "$TEMPLATES/brief-reviewer.md")
  for item in "Matches intent" "Code and comment quality" "Checks run clean" "No debris" "Scope discipline" "Project docs addressed" "Doc quality" "Commit conventions"; do
    [[ $RB == *"**$item.**"* ]] || { echo "brief lacks item: $item" >&2; return 1; }
  done
  for needle in "Run the project's own check command" "git reset --hard && git clean -fd" "git switch --detach <sha>" \
      "full diff \`git diff <base>...<sha>\`" "never conclusions to repeat or a PASS to carry forward" \
      "Verdict: PASS | FAIL" "Prior findings:" "done: round N PASS @<sha7>" "done: round N FAIL (<n> blocking) @<sha7>" \
      "working: round N" "A FAIL verdict is still \`done\`" "never push, post, comment, merge or edit project files" \
      "AI-attribution trailer is a FAIL" "Check the skills available to you" \
      "is a standard to judge the diff and its commits against" "never carry out its steps" \
      "A skill the diff adds or changes is under review, not a standard"; do
    [[ $RB == *"$needle"* ]] || { echo "brief lacks: $needle" >&2; return 1; }
  done
  [[ $(tr A-Z a-z <<< "$RB") != *superpowers* && $RB != *"conventional-"* ]]
  run grep -qi claude <<< "${RB//CLAUDE.md/}"
  assert_failure
}

@test "the builder lifecycle and the dispatch skill carry the review loop" {
  BLC=$(cat "$TEMPLATES/lifecycle-builder.md")
  for needle in "chief-review.sh <id>" "every time (never automatic)" "review everything this session" "also discards its reviewer"; do
    [[ $BLC == *"$needle"* ]] || { echo "lifecycle lacks: $needle" >&2; return 1; }
  done
  DS=$(cat "$REPO_ROOT/plugins/chief/skills/dispatch/SKILL.md")
  for needle in "## The review loop" "chief-review.sh <builder-id>" "There is no round cap"; do
    [[ $DS == *"$needle"* ]] || { echo "dispatch lacks: $needle" >&2; return 1; }
  done
  assert_not_exist "$REPO_ROOT/plugins/chief/skills/reviewer"
}
