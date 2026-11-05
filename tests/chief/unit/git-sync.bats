# git-sync.sh's chief_sync_default_branch: a best-effort fetch+ff-only-merge of
# a project's default branch against origin, that only ever acts when the
# checkout is on that branch with a clean tree, and never fails its caller.

setup() {
  load ../lib/common
  . "$BIN/lib/git-sync.sh"
  W="$BATS_TEST_TMPDIR"
}

commit() { git -C "$1" commit --allow-empty -q -m "$2"; }

@test "sync: succeeds without an origin" {
  git init -q -b main "$W/no-origin"
  commit "$W/no-origin" init
  run chief_sync_default_branch "$W/no-origin"
  assert_success
}

@test "sync: fast-forwards the default branch when checked out clean" {
  project_with_origin "$W/project"
  run chief_sync_default_branch "$W/project"
  assert_success
  assert_equal "$(git -C "$W/project" rev-parse main)" "$(git -C "$W/origin.git" rev-parse main)"
}

@test "sync: skips the default branch while another branch is checked out" {
  project_with_origin "$W/project"
  git -C "$W/project" checkout -q -b feature
  before=$(git -C "$W/project" rev-parse main)
  run chief_sync_default_branch "$W/project"
  assert_success
  assert_equal "$(git -C "$W/project" rev-parse main)" "$before"
}

@test "sync: skips the default branch with a dirty tree" {
  project_with_origin "$W/project"
  echo dirty > "$W/project/dirty.txt"
  before=$(git -C "$W/project" rev-parse main)
  run chief_sync_default_branch "$W/project"
  assert_success
  assert_equal "$(git -C "$W/project" rev-parse main)" "$before"
}

@test "sync: succeeds without merging when the history diverged" {
  project_with_origin "$W/project"
  commit "$W/project" "local-only work"
  commit "$W/other" "diverging origin work"
  git -C "$W/other" push -q origin main
  before=$(git -C "$W/project" rev-parse main)
  run chief_sync_default_branch "$W/project"
  assert_success
  assert_equal "$(git -C "$W/project" rev-parse main)" "$before"
}
