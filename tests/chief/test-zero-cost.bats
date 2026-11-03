# The guard that keeps paid agent CLIs out of every server the suite starts.

setup() {
  load lib/common
  chief_common_setup
}

@test "the guard refuses a PATH holding a real agent CLI" {
  mkdir "$BATS_TEST_TMPDIR/real"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/real/claude"; chmod +x "$BATS_TEST_TMPDIR/real/claude"
  run chief_zero_cost_guard "$STANDIN_BIN:$BATS_TEST_TMPDIR/real:/usr/bin:/bin"
  assert_success
  run chief_zero_cost_guard "$BATS_TEST_TMPDIR/real:$STANDIN_BIN:/usr/bin:/bin"
  assert_failure
  assert_output --partial "'claude' resolves to $BATS_TEST_TMPDIR/real/claude"
}

@test "the guard accepts a PATH with only the stand-ins" {
  run chief_zero_cost_guard "$STANDIN_BIN:/usr/bin:/bin"
  assert_success
}

@test "a server start aborts when a real agent CLI is on its PATH" {
  mkdir "$BATS_TEST_TMPDIR/real" "$BATS_TEST_TMPDIR/standins"  # the server PATH gets herdr's own directory
  ln -s "$(command -v herdr)" "$BATS_TEST_TMPDIR/real/herdr"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/real/codex"; chmod +x "$BATS_TEST_TMPDIR/real/codex"
  ln -s "$STANDIN_BIN/claude" "$BATS_TEST_TMPDIR/standins/claude"  # no codex stand-in to shadow it
  STANDIN_BIN="$BATS_TEST_TMPDIR/standins" PATH="$BATS_TEST_TMPDIR/real:$PATH" run chief_herdr_server
  assert_failure
  assert_output --partial "zero-cost guard: 'codex'"
  assert_not_exist "$BATS_TEST_TMPDIR/herdr-dir"
}
