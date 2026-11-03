# chief-teardown.sh's branches on a real herdr: a researcher's unconditional
# discard (its deliverable is its report outside the worktree, so there is
# nothing to prove "landed"), a builder's explicit --abandon override, the
# "landed" checks (merge, squash), and what a teardown keeps. The ordinary
# refuse-then-succeed path is covered end to end in test-lifecycle.bats.

setup() {
  load lib/common
  chief_common_setup
  chief_project
  GC=(git -c user.email=t@t -c user.name=t)
  BL="$BIN/chief-backlog.sh"
  TD="$BIN/chief-teardown.sh"
}

teardown() { chief_herdr_stop; }

spawn_mode() {  # <id> <mode> <branch> [spec]
  "$BL" add "$1" "Task $1" >/dev/null
  timeout 90 "$BIN/chief-spawn.sh" "$1" "$WORK/project" --mode "$2" --branch "$3" --intent "Task $1" --spec "content: $1" >/dev/null
}
commit_file() {  # <id> <file> <content>
  ( cd "$CHIEF_HOME/worktrees/$1" && echo "$3" > "$2" && git add "$2" && "${GC[@]}" commit -q -m "add $2" )
}
# origin_for_project - a bare origin the project (and so its worktrees) pushes to
origin_for_project() {
  BARE="$WORK/origin.git"
  git init -q --bare "$BARE"
  git -C "$WORK/project" remote add origin "$BARE"
  git -C "$WORK/project" push -q origin master
}
spawn_pushed() {  # <id> <mode> <branch>
  spawn_mode "$1" "$2" "$3"
  ( cd "$CHIEF_HOME/worktrees/$1" && echo "$1" > "$1.txt" && git add "$1.txt" \
      && "${GC[@]}" commit -q -m "add $1.txt" && git push -q origin "$3" )
  run git -C "$BARE" branch --list "$3"
  assert_output --partial "$3"
}

@test "a researcher tears down unconditionally, even with an unlanded commit; its report is archived" {
  spawn_mode s-1 researcher feat/s-1
  run cat "$CHIEF_HOME/tasks/s-1/lifecycle"
  assert_output --partial "handed off to a successor"
  echo "findings: use an LRU cache" > "$CHIEF_HOME/tasks/s-1/report.md"
  commit_file s-1 scratch.txt scratch
  echo "done: wrote report.md" >> "$CHIEF_HOME/tasks/s-1/status"
  run "$TD" s-1
  assert_success
  assert_not_exist "$CHIEF_HOME/worktrees/s-1"
  assert_not_exist "$CHIEF_HOME/tasks/s-1"
  assert_equal "$(cat "$CHIEF_HOME/archive/s-1/report.md")" "findings: use an LRU cache"
  run cat "$CHIEF_HOME/archive/s-1/meta"
  assert_output --partial "status=torn-down"
  run "$BL" show s-1
  assert_output --partial "[done]"
}

@test "a builder is refused without --abandon, even after done; --abandon force-discards it" {
  spawn_mode b-1 builder feat/b-1
  commit_file b-1 hello.txt hello
  echo "done: added hello.txt" >> "$CHIEF_HOME/tasks/b-1/status"
  run "$TD" b-1
  assert_failure
  assert_exist "$CHIEF_HOME/worktrees/b-1"
  run "$TD" b-1 --abandon
  assert_success
  assert_not_exist "$CHIEF_HOME/worktrees/b-1"
  run git -C "$WORK/project" worktree list
  refute_output --partial "worktrees/b-1"
  run "$BL" show b-1
  assert_output --partial "[done]"
}

@test "an already-landed builder doesn't need --abandon" {
  spawn_mode b-2 builder feat/b-2
  commit_file b-2 world.txt world
  git -C "$WORK/project" merge --ff-only feat/b-2 >/dev/null
  run "$TD" b-2
  assert_success
}

@test "a squash-merged builder lands via the git-only check; an unmerged one is refused" {
  spawn_mode b-3 builder feat/b-3
  commit_file b-3 moon.txt moon
  run "$TD" b-3
  assert_failure
  assert_exist "$CHIEF_HOME/worktrees/b-3"
  git -C "$WORK/project" merge --squash feat/b-3 >/dev/null
  "${GC[@]}" -C "$WORK/project" commit -q -m "squash feat/b-3"
  run "$TD" b-3
  assert_success
  assert_not_exist "$CHIEF_HOME/worktrees/b-3"
  run "$BL" show b-3
  assert_output --partial "[done]"
}

@test "squash-merged then reworked on the default branch: unprovable, refused until --abandon" {
  spawn_mode b-5 builder feat/b-5
  commit_file b-5 star.txt star
  git -C "$WORK/project" merge --squash feat/b-5 >/dev/null
  "${GC[@]}" -C "$WORK/project" commit -q -m "squash feat/b-5"
  echo "bright star" > "$WORK/project/star.txt"
  "${GC[@]}" -C "$WORK/project" commit -q -am "rework star.txt"
  run "$TD" b-5
  assert_failure
  assert_exist "$CHIEF_HOME/worktrees/b-5"
  run "$TD" b-5 --abandon
  assert_success
}

@test "the remote branch is kept when a landed builder is torn down" {
  origin_for_project
  spawn_pushed b-4 builder feat/b-4
  git -C "$WORK/project" merge --ff-only feat/b-4 >/dev/null
  run "$TD" b-4
  assert_success
  run git -C "$BARE" branch --list feat/b-4
  assert_output --partial "feat/b-4"
}

@test "the remote branch is kept on --abandon and when a researcher is torn down" {
  origin_for_project
  spawn_pushed p-5 builder feat/p-5
  spawn_pushed p-8 researcher feat/p-8
  run "$TD" p-5 --abandon
  assert_success
  run "$TD" p-8
  assert_success
  run git -C "$BARE" branch --list
  assert_output --partial "feat/p-5"
  assert_output --partial "feat/p-8"
}

@test "a builder tears down with its reviewer; both remote branches are kept" {
  origin_for_project
  spawn_pushed p-9 builder feat/p-9
  spawn_pushed p-9-review reviewer chore/review-p-9
  ( . "$BIN/lib/paths.sh"; . "$BIN/lib/meta.sh"; chief_meta_set p-9 reviewer p-9-review )
  run "$TD" p-9 --abandon
  assert_success
  assert_not_exist "$CHIEF_HOME/worktrees/p-9-review"
  run git -C "$BARE" branch --list
  assert_output --partial "feat/p-9"
  assert_output --partial "chore/review-p-9"
}

@test "a brainstormer discards like a researcher; re-running on an archived task completes" {
  timeout 90 "$BIN/chief-spawn.sh" bs-1 "$WORK/project" --mode brainstormer --branch feat/bs-1 --intent x >/dev/null
  run "$TD" bs-1
  assert_success
  run "$TD" bs-1
  assert_output --partial "torn down: bs-1"
  assert_exist "$CHIEF_HOME/archive/bs-1/meta"
}

@test "teardown releases the task's pre-trusted worktree" {
  trusted() { jq -r --arg p "$CHIEF_HOME/worktrees/p-1" '.projects[$p].hasTrustDialogAccepted // "unset"' "$CLAUDE_CONFIG_DIR/.claude.json"; }
  timeout 90 "$BIN/chief-spawn.sh" p-1 "$WORK/project" --mode researcher --branch feat/p-1 --intent x >/dev/null
  assert_equal "$(trusted)" true
  "$TD" p-1 >/dev/null
  assert_equal "$(trusted)" unset
}
