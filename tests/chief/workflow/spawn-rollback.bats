# chief-spawn.sh's rollback-on-failure and spawn lock (issue #16, item 2), on a
# real herdr. The agent never rendering its TUI (the stand-in's never-ready mode)
# and a failing `herdr agent start` (a wrapper around the real herdr) both fail
# the spawn AFTER the worktree, branch and herdr workspace exist.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  export CHIEF_HERDR_START_WAIT=3
}

teardown() { chief_herdr_stop; }

branches() { git -C "$WORK/project" branch --list | wc -l | tr -d ' '; }
spawn_raw() {  # <id> [flags...]
  local id=$1; shift
  "$BIN/chief-spawn.sh" "$id" "$WORK/project" --mode builder --branch "feat/$id" --intent "x" "$@"
}
assert_rolled_back() {  # <id>
  assert_not_exist "$CHIEF_HOME/worktrees/$1"
  assert_not_exist "$CHIEF_HOME/tasks/$1/meta"
  assert_not_exist "$CHIEF_HOME/tasks/$1/spawning"
  run git -C "$WORK/project" branch --list
  refute_output --partial "feat/$1"
  assert_equal "$(jq -r --arg p "$CHIEF_HOME/worktrees/$1" '.projects[$p].hasTrustDialogAccepted // "unset"' "$CLAUDE_CONFIG_DIR/.claude.json")" unset
  assert_equal "$(grep -c "$1" "$CHIEF_HOME/state/trust-owned" 2>/dev/null || true)" 0
  run herdr workspace list
  refute_output --partial "\"$1\""
}

@test "fails without --branch, leaving nothing behind" {
  run "$BIN/chief-spawn.sh" t-nobranch "$WORK/project" --mode builder --intent "no branch"
  assert_failure
  assert_not_exist "$CHIEF_HOME/worktrees/t-nobranch"
  assert_not_exist "$CHIEF_HOME/tasks/t-nobranch/meta"
  assert_not_exist "$CHIEF_HOME/tasks/t-nobranch/status"
  assert_not_exist "$CHIEF_HOME/tasks/t-nobranch/spawning"
  assert_equal "$(branches)" 1
}

@test "an existing --branch is refused and survives untouched" {
  git -C "$WORK/project" branch feat/t-exists
  sha=$(git -C "$WORK/project" rev-parse feat/t-exists)
  run spawn_raw t-exists
  assert_failure
  assert_equal "$(git -C "$WORK/project" rev-parse feat/t-exists)" "$sha"
  assert_not_exist "$CHIEF_HOME/worktrees/t-exists"
  assert_not_exist "$CHIEF_HOME/tasks/t-exists/meta"
  assert_not_exist "$CHIEF_HOME/tasks/t-exists/status"
  assert_not_exist "$CHIEF_HOME/tasks/t-exists/spawning"
}

@test "an agent that never renders rolls the worktree, branch, workspace and pre-trust back" {
  standin_mode t-fail never-ready
  run spawn_raw t-fail
  assert_failure
  assert_rolled_back t-fail
}

@test "a failing 'herdr agent start' rolls everything back too" {
  herdr_fault "agent start" 1000 before 1 '{"error":{"code":"internal","message":"boom"}}'
  run spawn_raw t-fail
  assert_failure
  assert_output --partial "'herdr agent start' failed for t-fail"
  assert_rolled_back t-fail
}

@test "a backend_spawn that returns malformed output after a real spawn is rolled back" {
  # a plugin copy whose herdr adapter drops the endpoint line of a real backend_spawn
  cp -r "$REPO_ROOT/plugins/chief" "$WORK/plugin-copy"
  cat >> "$WORK/plugin-copy/bin/lib/backends/herdr.sh" <<'PATCH'
eval "$(declare -f backend_spawn | sed '1s/backend_spawn/_real_backend_spawn/')"
backend_spawn() { _real_backend_spawn "$@" | head -n1; }
PATCH
  run "$WORK/plugin-copy/bin/chief-spawn.sh" t-malformed "$WORK/project" --mode builder --branch feat/t-malformed --intent x
  assert_failure
  assert_output --partial "backend_spawn returned malformed output"
  assert_rolled_back t-malformed
}

@test "an interrupted spawn's status=spawning stub: blocked in crew-state, surfaced by watch, cleaned by teardown --abandon" {
  mkdir -p "$CHIEF_HOME/tasks/t-stub"
  printf 'project=%s\nmode=builder\nbranch=chief/t-stub\nworktree=%s\nstatus=spawning\n' \
    "$WORK/project" "$CHIEF_HOME/worktrees/t-stub" > "$CHIEF_HOME/tasks/t-stub/meta"
  run "$BIN/task/chief-crew-state.sh" t-stub
  assert_output --partial "state: blocked"
  run timeout 10 "$BIN/chief-watch.sh"
  assert_output --partial "t-stub: state: blocked"
  : > "$CHIEF_HOME/tasks/t-stub/spawning"
  run "$BIN/task/chief-crew-state.sh" t-stub
  assert_output --partial "state: working"   # the spawn lock is held: a live spawn
  rm -f "$CHIEF_HOME/tasks/t-stub/spawning"
  run "$BIN/chief-teardown.sh" t-stub --abandon
  assert_success
  run cat "$CHIEF_HOME/archive/t-stub/meta"
  assert_output --partial "status=torn-down"
}

@test "the spawn lock: a same-id spawn is refused while it is held, then succeeds; the lock is always released" {
  mkdir -p "$CHIEF_HOME/state" "$CHIEF_HOME/tasks/t-locked"
  : > "$CHIEF_HOME/tasks/t-locked/spawning"
  run spawn_raw t-locked
  assert_failure
  assert_not_exist "$CHIEF_HOME/worktrees/t-locked"   # never reached the backend
  assert_not_exist "$CHIEF_HOME/tasks/t-locked/meta"
  rm -f "$CHIEF_HOME/tasks/t-locked/spawning"
  run spawn_raw t-locked
  assert_success
  assert_not_exist "$CHIEF_HOME/tasks/t-locked/spawning"
}

@test "the lock is released after a failed spawn" {
  standin_mode t-fail never-ready
  run spawn_raw t-fail
  assert_failure
  assert_not_exist "$CHIEF_HOME/tasks/t-fail/spawning"
}

@test "--dry-run and usage errors create nothing, not even the empty dirs" {
  FRESH="$BATS_TEST_TMPDIR/fresh/.chief"
  CHIEF_HOME="$FRESH" run spawn_raw t-dry --dry-run
  assert_success
  CHIEF_HOME="$FRESH" run "$BIN/chief-spawn.sh"
  assert_failure
  assert_not_exist "$FRESH"
}
