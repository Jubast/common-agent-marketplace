# The full happy path end to end on a real herdr: file a backlog item, spawn,
# simulate the builder's own work, confirm teardown refuses before a merge
# exists, merge, then confirm teardown succeeds and cleans up. This is the
# scenario a real dispatch actually goes through.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  BL="$BIN/chief-backlog.sh"
}

teardown() { chief_herdr_stop; }

@test "backlog -> spawn -> work -> refused teardown -> merge -> teardown" {
  run "$BL" add t-1 "Add hello.txt"
  assert_success
  run "$BL" list
  assert_output --partial "[queued]"

  spawn t-1 --intent "Add hello.txt" --spec "content: hello"
  run "$BL" show t-1
  assert_output --partial "[in-flight]"
  assert_exist "$CHIEF_HOME/worktrees/t-1"
  assert_exist "$CHIEF_HOME/tasks/t-1/brief.md"
  run cat "$CHIEF_HOME/tasks/t-1/brief.md"
  assert_output --partial "Add hello.txt"
  assert_output --partial "report \`working"  # re-announce working after resuming from a terminal status

  ( cd "$CHIEF_HOME/worktrees/t-1" && echo hello > hello.txt && git add hello.txt \
      && git commit -q -m "add hello.txt" )
  echo "done: added hello.txt" >> "$CHIEF_HOME/tasks/t-1/status"
  run "$BIN/task/chief-crew-state.sh" t-1
  assert_output --partial "state: done"

  run "$BIN/chief-teardown.sh" t-1
  assert_failure
  assert_exist "$CHIEF_HOME/worktrees/t-1"

  git -C "$WORK/project" merge --ff-only feat/t-1
  assert_equal "$(cat "$WORK/project/hello.txt")" hello

  run "$BIN/chief-teardown.sh" t-1
  assert_success
  assert_not_exist "$CHIEF_HOME/worktrees/t-1"
  run git -C "$WORK/project" worktree list
  refute_output --partial "worktrees/t-1"
  run "$BL" show t-1
  assert_output --partial "[done]"
}
