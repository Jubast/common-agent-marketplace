# chief_is_linked_worktree, the check that keeps Chief's identity/supervision
# hooks from misfiring inside a spawned builder's own worktree. Race-free
# (git-dir vs git-common-dir), so it's testable with plain git.

setup() {
  load lib/common
  . "$CHIEF_BIN/lib/worktree.sh"
  W="$BATS_TEST_TMPDIR"
  mkdir -p "$W/main" && cd "$W/main"
  git init -q -b main
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  git worktree add -q -b feature "$W/linked"
}

@test "the main checkout is NOT reported as a linked worktree" {
  cd "$W/main"
  run chief_is_linked_worktree
  assert_failure 1
}

@test "a linked worktree IS reported as one" {
  cd "$W/linked"
  run chief_is_linked_worktree
  assert_success
}

@test "a plain non-git directory is not reported as a linked worktree" {
  cd "$W"
  run chief_is_linked_worktree
  assert_failure 1
}

@test "an explicit dir argument is judged instead of the cwd" {
  cd "$W/main"
  run chief_is_linked_worktree "$W/linked"
  assert_success
}

@test "an explicit main-checkout dir is not linked even when the cwd is" {
  cd "$W/linked"
  run chief_is_linked_worktree "$W/main"
  assert_failure 1
}
