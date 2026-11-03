# common.bash - shared setup for Chief's .bats files: a real herdr per test,
# running the zero-cost stand-in agent (fixtures/standin/), never a paid CLI.
# `load lib/common` from setup(); call chief_common_setup, then chief_project.
TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugins/chief/bin"
CHIEF_BIN="$BIN"
STANDIN_BIN="$TEST_DIR/fixtures/standin"

bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

# chief_zero_cost_guard <path> - fails unless claude/codex/copilot resolve on
# <path> to a stand-in or nothing.
chief_zero_cost_guard() {
  local cli found
  for cli in claude codex copilot; do
    found=$(PATH=$1 command -v "$cli" || true)
    [ -z "$found" ] || [ "$found" = "$STANDIN_BIN/$cli" ] \
      || { echo "zero-cost guard: '$cli' resolves to $found, not a stand-in" >&2; return 1; }
  done
}

# chief_common_setup - per-test dirs, own CLAUDE_CONFIG_DIR, stand-ins first on
# PATH, and none of the outer herdr's HERDR_* variables.
chief_common_setup() {
  local v
  for v in $(compgen -e | grep '^HERDR_'); do unset "$v"; done
  export HERDR_SOCKET_PATH="$BATS_TEST_TMPDIR/none.sock"  # never the operator's herdr
  WORK="$BATS_TEST_TMPDIR/work"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude-config" STANDIN_DIR="$BATS_TEST_TMPDIR/standin"
  mkdir -p "$WORK" "$CLAUDE_CONFIG_DIR" "$STANDIN_DIR/modes" "$STANDIN_DIR/hold"
  PATH="$STANDIN_BIN:$PATH"
}

# chief_herdr_server - starts this test's own headless herdr. Panes inherit the
# SERVER's env, so it gets a scrubbed one: own HOME/XDG, a PATH whose only agent
# CLIs are the stand-ins, no network (herdr falls back to its built-in rules).
chief_herdr_server() {
  local d i server_path
  server_path="$STANDIN_BIN:$(dirname "$(command -v herdr)"):$(dirname "$(command -v jq)"):/usr/bin:/bin"
  chief_zero_cost_guard "$server_path" || return 1
  d=$(mktemp -d "${TMPDIR:-/tmp}/chs.XXXX")  # sun_path caps the socket path at 107 bytes
  echo "$d" > "$BATS_TEST_TMPDIR/herdr-dir"
  echo "$d $STANDIN_DIR" >> "$BATS_SUITE_TMPDIR/servers"  # for setup_suite's teardown_suite sweep
  mkdir -p "$d/home" "$d/xc" "$d/xr" "$d/xd"
  chmod 700 "$d/xr"
  export HERDR_SOCKET_PATH="$d/xr/h.sock"
  ( cd "$d" && env -i HOME="$d/home" XDG_CONFIG_HOME="$d/xc" XDG_RUNTIME_DIR="$d/xr" XDG_DATA_HOME="$d/xd" \
      HERDR_SOCKET_PATH="$HERDR_SOCKET_PATH" PATH="$server_path" TERM=xterm-256color \
      STANDIN_DIR="$STANDIN_DIR" STANDIN_TURN_SECS="${STANDIN_TURN_SECS:-1}" \
      HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 \
      GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
      nohup herdr server > "$d/server.log" 2>&1 < /dev/null & echo $! > "$d/pid" )
  for i in $(seq 1 100); do [ -S "$HERDR_SOCKET_PATH" ] && return 0; sleep 0.05; done
  echo "herdr server did not come up" >&2
  return 1
}

# chief_herdr_stop - stops this test's server; fails if it or a stand-in outlives it.
chief_herdr_stop() {
  local d pid f rc=0
  d=$(cat "$BATS_TEST_TMPDIR/herdr-dir" 2>/dev/null) || return 0
  HERDR_SOCKET_PATH="$d/xr/h.sock" herdr server stop >/dev/null 2>&1
  pid=$(cat "$d/pid")
  for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo "herdr server $pid outlived 'server stop'" >&2; rc=1; fi
  sleep 0.2
  for f in "$STANDIN_DIR"/*.pid; do
    [ -e "$f" ] || continue
    if kill -0 "$(cat "$f")" 2>/dev/null; then kill "$(cat "$f")"; echo "stand-in $(cat "$f") outlived its server" >&2; rc=1; fi
  done
  rm -rf "$d"
  return $rc
}

# chief_project - a git repo at $WORK/project, CHIEF_HOME and the herdr backend.
chief_project() {
  mkdir -p "$WORK/project"
  git -C "$WORK/project" init -q -b master
  git -C "$WORK/project" -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
  export CHIEF_HOME="$WORK/.chief" CHIEF_BACKEND=herdr
  chief_herdr_server
}

# spawn <id> [chief-spawn args] - a builder on feat/<id> in $WORK/project.
spawn() {
  local id=$1; shift
  timeout 90 "$BIN/chief-spawn.sh" "$id" "$WORK/project" --mode builder --branch "feat/$id" --intent "test" --spec "test" "$@" >/dev/null
}

# herdr_fault <call> [times] [stdout] - from now on the first [times] (1) calls
# of `herdr <call>` fail with [stdout]; every other call runs the real herdr.
herdr_fault() {
  export HERDR_REAL="$(command -v herdr)" HERDR_FAULT_CALL="$1" HERDR_FAULT_TIMES="${2:-1}" \
         HERDR_FAULT_OUT="${3:-}" HERDR_FAULT_COUNT="$BATS_TEST_TMPDIR/fault-count"
  rm -f "$HERDR_FAULT_COUNT"
  PATH="$TEST_DIR/fixtures/faulty:$PATH"
}

# standin_turns <id> - every turn the stand-in in that task's worktree received.
standin_turns() { cat "$STANDIN_DIR/$1.log" 2>/dev/null; }
# standin_keys <id> - the lone special keys (esc) the stand-in received.
standin_keys() { cat "$STANDIN_DIR/$1.keys" 2>/dev/null; }
# standin_mode <id> <mode>... - modes for the stand-in the next spawn of <id> starts.
standin_mode() { local id=$1; shift; printf '%s\n' "$@" > "$STANDIN_DIR/modes/$id"; }
# standin_hold <id> / standin_release <id> - keep the turn `working` / let it finish.
standin_hold() { : > "$STANDIN_DIR/hold/$1"; }
standin_release() { rm -f "$STANDIN_DIR/hold/$1"; }
# standin_type <id> <text> - types <text> into the agent's input line, no Enter.
standin_type() {
  herdr pane send-text "$(sed -n 's/^endpoint=herdr://p' "$CHIEF_HOME/tasks/$1/meta")" "$2" >/dev/null
}
# standin_kill <id> - the stand-in dies, as a crashed agent would.
standin_kill() { kill "$(cat "$STANDIN_DIR/$1.pid")"; }

# wait_settled <id> - waits for the agent's current turn (the brief) to finish.
wait_settled() {
  settled() { ! herdr agent get "$1" | jq -e '.result.agent.agent_status == "working"' >/dev/null; }
  eventually 20 settled "$1"
}

# eventually <secs> <cmd...> - retries <cmd> until it passes; real backends
# deliver mid-task sends and finish turns asynchronously. Never use a bare sleep.
eventually() {
  local secs=$1 i; shift
  for i in $(seq 1 $((secs * 4))); do "$@" >/dev/null 2>&1 && return 0; sleep 0.25; done
  "$@"
}
