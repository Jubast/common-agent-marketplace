# The guard every live file runs before it starts anything: its herdr is its
# own. Free (no model turn), but part of live/ since it starts a real herdr.

# bats file_tags=live

setup_file() {
  load ../lib/live
  load ../lib/common
  live_require herdr jq ss
  live_isolate
}
setup() {
  load ../lib/live
  load ../lib/common
  live_env
}
teardown_file() {
  load ../lib/live
  load ../lib/common
  live_stop
}

@test "guard: the scratch herdr is not the caller's and starts empty" {
  owner=$(live_sock_owner "$HERDR_SOCKET_PATH")
  [ "$owner" = "$(cat "$LIVE/server.pid")" ] || [ "$(ps -o ppid= -p "$owner" | tr -d ' ')" = "$(cat "$LIVE/server.pid")" ]
  [[ $HERDR_SOCKET_PATH == "$LIVE"/* ]]
  assert_equal "$(herdr workspace list | jq '.result.workspaces | length')" 0
}

@test "guard: refuses a socket outside the scratch dir" {
  HERDR_SOCKET_PATH=/tmp/elsewhere.sock run live_guard
  assert_failure 1
  assert_output --partial "outside the scratch dir"
}

@test "guard: refuses the caller's own socket" {
  HERDR_SOCKET_PATH="$LIVE/xdg-run/other.sock"
  LIVE_CALLER_SOCKS=("$HERDR_SOCKET_PATH")
  run live_guard
  assert_failure 1
  assert_output --partial "socket equals"
}

@test "guard: the scratch Chief home is inside the scratch dir, not the operator's" {
  live_guard_chief_home
  [[ $CHIEF_HOME == "$LIVE"/* ]]
  [[ $LIVE_REAL_CHIEF_HOME != "$LIVE"/* ]]
}

@test "guard: refuses a CHIEF_HOME outside the scratch dir" {
  CHIEF_HOME=$LIVE_REAL_CHIEF_HOME run live_guard_chief_home
  assert_failure 1
  assert_output --partial "outside the scratch dir"
}

@test "guard: refuses a CHIEF_HOME that is the operator's" {
  LIVE_REAL_CHIEF_HOME=$CHIEF_HOME run live_guard_chief_home
  assert_failure 1
  assert_output --partial "the operator's"
}
