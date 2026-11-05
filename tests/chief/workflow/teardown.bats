# chief-teardown.sh's branches on a real herdr: a researcher's unconditional
# discard (its deliverable is its report outside the worktree, so there is
# nothing to prove "landed"), a builder's explicit --abandon override, the
# "landed" checks (merge, squash), what a teardown keeps, and the reviewer
# cascade. The ordinary refuse-then-succeed path is covered end to end in
# lifecycle.bats.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  chief_herdr_server
  . "$BIN/lib/paths.sh"; . "$BIN/lib/meta.sh"
  BL="$BIN/chief-backlog.sh"
}

teardown() { chief_herdr_stop; }

td() { timeout 90 "$BIN/chief-teardown.sh" "$@"; }
# reviewed <id> - a done builder with its round 1 reviewer <id>-rv
reviewed() {
  chief_done_builder "$1"
  timeout 90 "$BIN/task/chief-review.sh" "$1" >/dev/null
}

spawn_mode() {  # <id> <mode> <branch>: filed in the backlog, then spawned
  "$BL" add "$1" "Task $1" >/dev/null
  chief_spawn "$1" "$2" --branch "$3" --intent "Task $1" --spec "content: $1" >/dev/null
}
spawn_pushed() {  # <id> <mode> <branch>
  spawn_mode "$1" "$2" "$3"
  commit_file "$1" "$1.txt" "$1" >/dev/null
  git -C "$CHIEF_HOME/worktrees/$1" push -q origin "$3"
  run git -C "$BARE" branch --list "$3"
  assert_output --partial "$3"
}

@test "researcher: tears down unconditionally and archives its report" {
  spawn_mode s-1 researcher feat/s-1
  echo "findings: use an LRU cache" > "$CHIEF_HOME/tasks/s-1/report.md"
  commit_file s-1 scratch.txt scratch
  echo "done: wrote report.md" >> "$CHIEF_HOME/tasks/s-1/status"
  run td s-1
  assert_success
  assert_not_exist "$CHIEF_HOME/worktrees/s-1"
  assert_not_exist "$CHIEF_HOME/tasks/s-1"
  assert_equal "$(cat "$CHIEF_HOME/archive/s-1/report.md")" "findings: use an LRU cache"
  run cat "$CHIEF_HOME/archive/s-1/meta"
  assert_output --partial "status=torn-down"
  run "$BL" show s-1
  assert_output --partial "[done]"
}

@test "builder: is refused without --abandon, even after done" {
  spawn_mode b-1 builder feat/b-1
  commit_file b-1 hello.txt hello
  echo "done: added hello.txt" >> "$CHIEF_HOME/tasks/b-1/status"
  run td b-1
  assert_failure 1
  assert_exist "$CHIEF_HOME/worktrees/b-1"
  run td b-1 --abandon
  assert_success
  assert_not_exist "$CHIEF_HOME/worktrees/b-1"
  run git -C "$WORK/project" worktree list
  refute_output --partial "worktrees/b-1"
  run "$BL" show b-1
  assert_output --partial "[done]"
}

@test "builder: a landed one tears down without --abandon" {
  spawn_mode b-2 builder feat/b-2
  commit_file b-2 world.txt world
  git -C "$WORK/project" merge --ff-only feat/b-2 >/dev/null
  run td b-2
  assert_success
}

@test "builder: a squash-merged one lands, an unmerged one is refused" {
  spawn_mode b-3 builder feat/b-3
  commit_file b-3 moon.txt moon
  run td b-3
  assert_failure 1
  assert_exist "$CHIEF_HOME/worktrees/b-3"
  git -C "$WORK/project" merge --squash feat/b-3 >/dev/null
  git -C "$WORK/project" commit -q -m "squash feat/b-3"
  run td b-3
  assert_success
  assert_not_exist "$CHIEF_HOME/worktrees/b-3"
  run "$BL" show b-3
  assert_output --partial "[done]"
}

@test "builder: a squash-merged one reworked on the default branch needs --abandon" {
  spawn_mode b-5 builder feat/b-5
  commit_file b-5 star.txt star
  git -C "$WORK/project" merge --squash feat/b-5 >/dev/null
  git -C "$WORK/project" commit -q -m "squash feat/b-5"
  echo "bright star" > "$WORK/project/star.txt"
  git -C "$WORK/project" commit -q -am "rework star.txt"
  run td b-5
  assert_failure 1
  assert_exist "$CHIEF_HOME/worktrees/b-5"
  run td b-5 --abandon
  assert_success
}

@test "remote branch: kept when a landed builder is torn down" {
  chief_add_origin "$WORK/project" main
  spawn_pushed b-4 builder feat/b-4
  git -C "$WORK/project" merge --ff-only feat/b-4 >/dev/null
  run td b-4
  assert_success
  run git -C "$BARE" branch --list feat/b-4
  assert_output --partial "feat/b-4"
}

@test "remote branch: kept on --abandon and when a researcher is torn down" {
  chief_add_origin "$WORK/project" main
  spawn_pushed p-5 builder feat/p-5
  spawn_pushed p-8 researcher feat/p-8
  run td p-5 --abandon
  assert_success
  run td p-8
  assert_success
  run git -C "$BARE" branch --list
  assert_output --partial "feat/p-5"
  assert_output --partial "feat/p-8"
}

@test "remote branch: a builder's and its reviewer's are both kept" {
  chief_add_origin "$WORK/project" main
  spawn_pushed p-9 builder feat/p-9
  spawn_pushed p-9-review reviewer chore/review-p-9
  chief_meta_set p-9 reviewer p-9-review
  run td p-9 --abandon
  assert_success
  assert_not_exist "$CHIEF_HOME/worktrees/p-9-review"
  run git -C "$BARE" branch --list
  assert_output --partial "feat/p-9"
  assert_output --partial "chore/review-p-9"
}

@test "brainstormer: discards like a researcher, and a re-run on the archive completes" {
  spawn bs-1 --mode brainstormer
  run td bs-1
  assert_success
  run td bs-1
  assert_output --partial "torn down: bs-1"
  assert_exist "$CHIEF_HOME/archive/bs-1/meta"
}

@test "pre-trust: released with the task's worktree" {
  spawn p-1 --mode researcher
  assert_equal "$(trusted "$CHIEF_HOME/worktrees/p-1")" true
  td p-1 >/dev/null
  assert_equal "$(trusted "$CHIEF_HOME/worktrees/p-1")" unset
}

@test "cascade: a landed builder takes its reviewer with it" {
  reviewed b-1
  printf 'Verdict: PASS\n' > "$CHIEF_HOME/tasks/b-1-rv/report.md"
  git -C "$WORK/project" merge --ff-only feat/b-1 >/dev/null
  run td b-1
  assert_output --partial "torn down: b-1 "
  assert_output --partial "torn down: b-1-rv "
  assert_not_exist "$CHIEF_HOME/worktrees/b-1-rv"
  assert_equal "$(cat "$CHIEF_HOME/archive/b-1-rv/report.md")" "Verdict: PASS"
  run "$BL" show b-1-rv; assert_output --partial "[done]"
}

@test "cascade: a reviewer tears down alone and leaves its builder" {
  reviewed b-2
  run td b-2-rv
  assert_output --partial "torn down: b-2-rv "
  assert_equal "$(git -C "$WORK/project" worktree list | grep -c 'worktrees/b-2 ')" 1
}

@test "cascade: abandoning the builder does not tear a gone reviewer down twice" {
  reviewed b-2
  td b-2-rv >/dev/null
  run td b-2 --abandon
  assert_equal "$(grep -c '^torn down' <<< "$output")" 1
}

@test "cascade: a reviewer with its worktree removed by hand goes with its builder" {
  reviewed b-3
  git -C "$WORK/project" worktree remove --force "$CHIEF_HOME/worktrees/b-3-rv"
  run td b-3 --abandon
  assert_output --partial "torn down: b-3-rv "
  assert_equal "$(chief_meta_get b-3-rv status)" torn-down
  run "$BL" show b-3-rv; assert_output --partial "[done]"
  assert_equal "$(git -C "$WORK/project" branch --list chore/b-3-rv)" ""
}
