# git-sync.sh's chief_sync_default_branch: a best-effort fetch+ff-only-merge of
# a project's default branch against origin, that only ever acts when the
# checkout is on that branch with a clean tree, and never fails its caller.

setup() {
  load ../lib/common
  . "$CHIEF_BIN/lib/git-sync.sh"
  W="$BATS_TEST_TMPDIR"
}

commit() { git -C "$1" commit --allow-empty -q -m "$2"; }

# project_with_origin - $W/project on main, tracking $W/origin.git, with
# origin advanced by a second clone ($W/other) since the last fetch.
project_with_origin() {
  git init -q --bare -b main "$W/origin.git"
  git init -q -b main "$W/project"
  commit "$W/project" init
  git -C "$W/project" remote add origin "$W/origin.git"
  git -C "$W/project" push -q origin main
  git clone -q "$W/origin.git" "$W/other"
  commit "$W/other" "advance origin"
  git -C "$W/other" push -q origin main
}

@test "never fails the caller when there is no origin remote" {
  git init -q -b main "$W/no-origin"
  commit "$W/no-origin" init
  run chief_sync_default_branch "$W/no-origin"
  assert_success
}

@test "fast-forwards the local default branch when on it with a clean tree" {
  project_with_origin
  run chief_sync_default_branch "$W/project"
  assert_success
  assert_equal "$(git -C "$W/project" rev-parse main)" "$(git -C "$W/origin.git" rev-parse main)"
}

@test "leaves main untouched while another branch is checked out" {
  project_with_origin
  git -C "$W/project" checkout -q -b feature
  before=$(git -C "$W/project" rev-parse main)
  run chief_sync_default_branch "$W/project"
  assert_success
  assert_equal "$(git -C "$W/project" rev-parse main)" "$before"
}

@test "leaves main untouched with a dirty working tree" {
  project_with_origin
  echo dirty > "$W/project/dirty.txt"
  before=$(git -C "$W/project" rev-parse main)
  run chief_sync_default_branch "$W/project"
  assert_success
  assert_equal "$(git -C "$W/project" rev-parse main)" "$before"
}

@test "never fails when the ff-only merge can't apply (diverged history)" {
  project_with_origin
  commit "$W/project" "local-only work"
  commit "$W/other" "diverging origin work"
  git -C "$W/other" push -q origin main
  before=$(git -C "$W/project" rev-parse main)
  run chief_sync_default_branch "$W/project"
  assert_success
  assert_equal "$(git -C "$W/project" rev-parse main)" "$before"
}
