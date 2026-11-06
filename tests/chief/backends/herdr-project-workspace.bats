# The last teardown of a project closes its primary herdr workspace only when
# herdr created it for one of Chief's spawns (state/herdr-owned/), and it is
# still one idle shell pane. Everything else of the operator's stays open.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  chief_herdr_server
  . "$BIN/lib/paths.sh"; . "$BIN/lib/meta.sh"; . "$BIN/lib/agents/agent.sh"
  chief_ensure_dirs
  . "$BIN/lib/backends/herdr.sh"
  P="$WORK/project"
}

teardown() { chief_herdr_stop; }

td() { timeout 90 "$BIN/chief-teardown.sh" "$@"; }
sp() { chief_spawn_quiet "$1" --mode researcher; }
has_label() { herdr workspace list | jq -e --arg l "$1" 'any(.result.workspaces[]; .label == $l)' >/dev/null; }
# primary_id [dir] - the primary workspace of the project (or <dir>)
primary_id() {
  herdr workspace list | jq -r --arg p "${1:-$P}" \
    '.result.workspaces[] | select(.worktree.checkout_path == $p and .worktree.is_linked_worktree == false) | .workspace_id'
}
# operator_ws <dir> <label> - a workspace the operator opened in <dir>
operator_ws() { herdr workspace create --cwd "$1" --label "$2" --no-focus | jq -r .result.workspace.workspace_id; }
# task_ws <id> - the workspace of a task, from its endpoint
task_ws() { chief_meta_get "$1" endpoint | sed 's/herdr://; s/:.*//'; }
records() { ls -A "$STATE/herdr-owned" 2>/dev/null; }

# restart_herdr - stops this test's server and starts it again on the same state
restart_herdr() {
  local d server_path i
  d=$(cat "$BATS_TEST_TMPDIR/herdr-dir")
  herdr server stop >/dev/null 2>&1
  for i in $(seq 1 50); do kill -0 "$(cat "$d/pid")" 2>/dev/null || break; sleep 0.1; done
  rm -f "$HERDR_SOCKET_PATH"
  server_path="$STANDIN_BIN:$(dirname "$(command -v herdr)"):$(dirname "$(command -v jq)"):/usr/bin:/bin"
  ( cd "$d" && env -i HOME="$d/home" XDG_CONFIG_HOME="$d/xc" XDG_RUNTIME_DIR="$d/xr" XDG_DATA_HOME="$d/xd" \
      HERDR_SOCKET_PATH="$HERDR_SOCKET_PATH" PATH="$server_path" TERM=xterm-256color \
      STANDIN_DIR="$STANDIN_DIR" STANDIN_TURN_SECS=1 HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 \
      nohup herdr server >> "$d/server.log" 2>&1 < /dev/null & echo $! > "$d/pid" )
  for i in $(seq 1 100); do herdr workspace list >/dev/null 2>&1 && return 0; sleep 0.05; done
  return 1
}

@test "teardown: closes the Chief-created primary at the last teardown, not earlier" {
  sp a1; sp a2
  W=$(primary_id)
  [ -n "$W" ]
  td a1 >/dev/null
  assert_equal "$(primary_id)" "$W"
  td a2 >/dev/null
  assert_equal "$(primary_id)" ""
}

@test "teardown: keeps a workspace the operator opened on the project before the first spawn" {
  operator_ws "$P" mine >/dev/null
  sp a1
  td a1 >/dev/null
  has_label mine
}

@test "teardown: keeps a workspace the operator opened in a project subdirectory" {
  mkdir -p "$P/sub"
  operator_ws "$P/sub" mine >/dev/null
  sp a1
  td a1 >/dev/null
  has_label mine
}

@test "teardown: keeps Chief's own workspace on the project" {
  export HERDR_WORKSPACE_ID=$(operator_ws "$P" chief-own)
  sp a1
  td a1 >/dev/null
  has_label chief-own
}

@test "teardown: keeps a workspace the operator opened after Chief's primary was closed" {
  sp d1
  mkdir -p "$P/sub"
  operator_ws "$P/sub" mine >/dev/null
  td d1 >/dev/null
  sp d2
  td d2 >/dev/null
  has_label mine
}

@test "teardown: keeps a primary with a foreground process" {
  sp a1
  W=$(primary_id)
  PANE=$(herdr pane list --workspace "$W" | jq -r '.result.panes[0].pane_id')
  herdr pane run "$PANE" "sleep 4243" >/dev/null
  busy() { herdr pane process-info --pane "$PANE" | jq -e '.result.process_info | .foreground_process_group_id != .shell_pid' >/dev/null; }
  eventually busy
  td a1 >/dev/null
  assert_equal "$(primary_id)" "$W"
}

@test "teardown: keeps a primary with a second pane" {
  sp a1
  W=$(primary_id)
  PANE=$(herdr pane list --workspace "$W" | jq -r '.result.panes[0].pane_id')
  herdr pane split "$PANE" --direction right --no-focus >/dev/null
  td a1 >/dev/null
  assert_equal "$(primary_id)" "$W"
}

@test "teardown: keeps the operator's workspace that reuses a recorded id after a restart" {
  herdr workspace create --cwd "$WORK" --label keep --no-focus >/dev/null
  sp a1
  W=$(primary_id)
  herdr workspace close "$(task_ws a1)" >/dev/null
  herdr workspace close "$W" >/dev/null
  restart_herdr
  N=$(operator_ws "$P" mine)
  herdr worktree open --cwd "$P" --path "$CHIEF_HOME/worktrees/a1" --label a1 --no-focus >/dev/null
  chief_meta_set a1 endpoint "herdr:$(herdr workspace list | jq -r '.result.workspaces[] | select(.label == "a1") | .workspace_id'):p1"
  assert_equal "$N" "$W"
  td a1 >/dev/null
  has_label mine
}

@test "teardown: keeps a Chief-created primary that survived a server restart" {
  sp a1
  W=$(primary_id)
  herdr workspace close "$(task_ws a1)" >/dev/null
  restart_herdr
  td a1 >/dev/null
  assert_equal "$(primary_id)" "$W"
  assert_equal "$(records)" ""
}

@test "teardown: drops the record when the operator closed the primary" {
  sp a1
  herdr workspace close "$(task_ws a1)" >/dev/null
  herdr workspace close "$(primary_id)" >/dev/null
  td a1 >/dev/null
  assert_equal "$(records)" ""
}

@test "teardown: closes a primary reached through a symlink to the project" {
  ln -s "$P" "$WORK/link"
  PROJECT="$WORK/link" sp a1
  [ -n "$(primary_id "$WORK/link")" ]
  td a1 >/dev/null
  assert_equal "$(primary_id "$WORK/link")" ""
}

@test "teardown: leaves the primary quietly while the operator's worktree workspace is open" {
  sp a1
  W=$(primary_id)
  herdr worktree create --cwd "$P" --branch op-g --path "$WORK/op-g" --label op-g --no-focus >/dev/null
  run --separate-stderr td a1
  assert_equal "$stderr" ""
  assert_equal "$(primary_id)" "$W"
  herdr workspace close "$(herdr workspace list | jq -r '.result.workspaces[] | select(.label == "op-g") | .workspace_id')" >/dev/null
  sp a2
  td a2 >/dev/null
  assert_equal "$(primary_id)" ""
}

@test "teardown: warns with herdr's reason when the close fails" {
  sp a1
  chief_herdr_fault "workspace close" 2 before 1 '{"error":{"code":"internal","message":"boom"}}'
  run --separate-stderr td a1
  [[ $stderr == *boom* ]]
}

@test "spawn: records nothing when the workspace list before it fails" {
  chief_herdr_fault "workspace list" 1 before 1 ""
  sp a1
  [ -n "$(primary_id)" ]
  assert_equal "$(records)" ""
}

@test "spawn: records nothing when the workspace list before it is empty" {
  chief_herdr_fault "workspace list" 1 before 0 ""
  sp a1
  [ -n "$(primary_id)" ]
  assert_equal "$(records)" ""
}

@test "relaunch: a primary it re-creates is closed by the last teardown" {
  sp r1
  chief_agent_use r1 >/dev/null 2>&1
  backend_kill r1
  herdr workspace close "$(primary_id)" >/dev/null
  printf 'brief\n' > "$WORK/brief.md"
  run backend_relaunch r1 "$WORK/brief.md"
  assert_success
  [ -n "$(primary_id)" ]
  td r1 >/dev/null
  assert_equal "$(primary_id)" ""
}
