# chief_is_linked_worktree, the check that keeps Chief's identity/supervision
# hooks from misfiring inside a spawned builder's own worktree. Race-free
# (git-dir vs git-common-dir), so it's testable with plain git.

setup() {
  load ../lib/common
  . "$BIN/lib/worktree.sh"
  W="$BATS_TEST_TMPDIR"
  mkdir -p "$W/main" && cd "$W/main"
  git init -q -b main
  git commit --allow-empty -q -m init
  git worktree add -q -b feature "$W/linked"
}

@test "is_linked_worktree: false for the main checkout" {
  cd "$W/main"
  run chief_is_linked_worktree
  assert_failure 1
}

@test "is_linked_worktree: true for a linked worktree" {
  cd "$W/linked"
  run chief_is_linked_worktree
  assert_success
}

@test "is_linked_worktree: false for a non-git directory" {
  cd "$W"
  run chief_is_linked_worktree
  assert_failure 1
}

@test "is_linked_worktree: judges an explicit dir, not the cwd" {
  cd "$W/main"
  run chief_is_linked_worktree "$W/linked"
  assert_success
}

@test "is_linked_worktree: false for an explicit main checkout run from a linked cwd" {
  cd "$W/linked"
  run chief_is_linked_worktree "$W/main"
  assert_failure 1
}
