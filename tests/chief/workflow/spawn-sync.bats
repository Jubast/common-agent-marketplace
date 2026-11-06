# The spawn flow on a real herdr: origin sync before the task worktree exists,
# and all Chief state under CHIEF_HOME - never a .chief inside a project.

setup() {
  load ../lib/common
  chief_common_setup
  W="$BATS_TEST_TMPDIR"
  # A workspace repo with a project checkout nested inside (as projects/<repo>),
  # whose origin is ahead of the local checkout.
  mkdir -p "$W/ws/projects" && git -C "$W/ws" init -q -b main
  P="$W/ws/projects/app"
  chief_project_with_origin "$P"
  unset CHIEF_HOME
  export CHIEF_BACKEND=herdr
  chief_herdr_server
  HOME_DIR="$W/ws/.chief"
  PROJECT="$P"
}

teardown() { chief_herdr_stop; }

@test "spawn: state lands at the workspace root, on the synced origin" {
  cd "$P"
  run chief_spawn a-1 builder
  assert_success
  assert_exist "$HOME_DIR/tasks/a-1/meta"
  assert_not_exist "$P/.chief"
  assert_exist "$HOME_DIR/worktrees/a-1/from-origin.txt"
}

@test "backlog: run from a project or its worktree creates no .chief there" {
  cd "$P"
  chief_spawn_quiet b-1
  for dir in "$P" "$HOME_DIR/worktrees/b-1"; do
    run bash -c "cd '$dir' && '$BIN/chief-backlog.sh' add x-$RANDOM t"
    assert_success
    assert_not_exist "$dir/.chief"
  done
}
