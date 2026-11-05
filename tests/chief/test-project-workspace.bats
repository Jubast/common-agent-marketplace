# The spawn flow on a real herdr: origin sync before the task worktree exists,
# and all Chief state under CHIEF_HOME - never a .chief inside a project.

setup() {
  load lib/common
  chief_common_setup
  W="$BATS_TEST_TMPDIR"
  GIT=(git)
  # A workspace repo with a project checkout nested inside (as projects/<repo>),
  # whose origin is ahead of the local checkout.
  mkdir -p "$W/ws/projects" && git -C "$W/ws" init -q -b main
  git init -q --bare -b main "$W/origin.git"
  git clone -q "$W/origin.git" "$W/ws/projects/app" 2>/dev/null
  P="$W/ws/projects/app"
  "${GIT[@]}" -C "$P" commit --allow-empty -q -m init && git -C "$P" push -q origin main
  git clone -q "$W/origin.git" "$W/other"
  echo new > "$W/other/from-origin.txt"
  "${GIT[@]}" -C "$W/other" add . && "${GIT[@]}" -C "$W/other" commit -q -m "advance origin" && git -C "$W/other" push -q origin main
  unset CHIEF_HOME
  export CHIEF_BACKEND=herdr
  chief_herdr_server
  HOME_DIR="$W/ws/.chief"
}

teardown() { chief_herdr_stop; }

spawn_task() { timeout 90 "$BIN/chief-spawn.sh" "$1" "$P" --mode builder --branch "feat/$1" --intent "x"; }

@test "spawn from inside the project: state lands at the workspace root, the worktree branches from the synced origin" {
  cd "$P"
  run spawn_task a-1
  assert_success
  assert_exist "$HOME_DIR/tasks/a-1/meta"
  assert_not_exist "$P/.chief"
  assert_exist "$HOME_DIR/worktrees/a-1/from-origin.txt"
}

@test "backlog from a project and from its worktree creates no .chief there" {
  cd "$P"
  spawn_task b-1 >/dev/null
  for dir in "$P" "$HOME_DIR/worktrees/b-1"; do
    run bash -c "cd '$dir' && '$BIN/chief-backlog.sh' add x-$RANDOM t"
    assert_success
    assert_not_exist "$dir/.chief"
  done
}
