# common.bash - shared setup for Chief's .bats files: a real herdr per test,
# running the zero-cost stand-in agent (fixtures/standin/), never a paid CLI.
# `load lib/common` from setup() or setup_file(); call chief_common_setup, then chief_project.

# chief_isolate - runs when this file is loaded: nothing from the caller's
# environment (an operator's herdr, a Chief worker's CHIEF_*, a git identity)
# reaches a test. Per-test paths need BATS_TEST_TMPDIR, so setup_file skips them.
chief_isolate() {
  local v
  for v in $(compgen -e | grep -E '^(HERDR_|CHIEF_)' | grep -v '^CHIEF_TEST_'); do unset "$v"; done
  unset CLAUDE_PROJECT_DIR
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
         GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  [ -n "${BATS_TEST_TMPDIR:-}" ] || return 0
  export HERDR_SOCKET_PATH="$BATS_TEST_TMPDIR/none.sock"  # never the operator's herdr
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude-config"
}
chief_isolate

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# chief_common_setup - per-test dirs and stand-ins first on PATH (the
# environment was isolated when this file was loaded).
chief_common_setup() {
  WORK="$BATS_TEST_TMPDIR/work"
  export STANDIN_DIR="$BATS_TEST_TMPDIR/standin"
  mkdir -p "$WORK" "$CLAUDE_CONFIG_DIR" "$STANDIN_DIR/modes" "$STANDIN_DIR/hold"
  PATH="$STANDIN_BIN:$PATH"
}

# chief_herdr_require - skips the test without herdr, unless
# CHIEF_TEST_REQUIRE_BACKENDS=1 (CI), where that is a failure.
chief_herdr_require() {
  command -v herdr > /dev/null && return 0
  [ "${CHIEF_TEST_REQUIRE_BACKENDS:-}" != 1 ] || { echo "herdr missing but required" >&2; return 1; }
  skip "herdr not installed (tests/chief/ci/install-herdr.sh)"
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
  [ -n "${BATS_TEST_COMPLETED:-}" ] || tail -n 20 "$d/server.log" >&2
  rm -rf "$d"
  return $rc
}

# chief_project - a git repo at $WORK/project, CHIEF_HOME and the herdr backend.
chief_project() {
  mkdir -p "$WORK/project"
  git -C "$WORK/project" init -q -b master
  git -C "$WORK/project" commit --allow-empty -q -m init
  export CHIEF_HOME="$WORK/.chief" CHIEF_BACKEND=herdr
  chief_herdr_server
}

# spawn <id> [chief-spawn args] - a builder on feat/<id> in $WORK/project.
spawn() {
  local id=$1; shift
  timeout 90 "$BIN/chief-spawn.sh" "$id" "$WORK/project" --mode builder --branch "feat/$id" --intent "test" --spec "test" "$@" >/dev/null
}

# chief_spawn <id> <role> [chief-spawn flags...] - chief-spawn.sh on feat/<id> in
# ${PROJECT:-$WORK/project}; later flags override the defaults. Output goes to
# the caller: use `run`, or redirect it.
chief_spawn() {
  local id=$1 role=$2; shift 2
  timeout 90 "$BIN/chief-spawn.sh" "$id" "${PROJECT:-$WORK/project}" --mode "$role" \
    --branch "feat/$id" --intent "intent of $id" --spec "spec of $id" "$@"
}
# chief_done_builder <id> [file] - a builder with one commit and a done line
# carrying its sha, filed in the backlog as "T <id>".
chief_done_builder() {
  "$BIN/chief-backlog.sh" add "$1" "T $1" >/dev/null
  chief_spawn "$1" builder --intent "T $1" >/dev/null
  commit_file "$1" "${2:-$1.txt}" >/dev/null
  echo "done: $(git -C "$CHIEF_HOME/worktrees/$1" rev-parse --short HEAD) ok" >> "$CHIEF_HOME/tasks/$1/status"
}

# commit_file <id> <file> [content] - commits a file in the task's worktree and
# prints the new sha.
commit_file() {
  ( cd "$CHIEF_HOME/worktrees/$1" && echo "${3:-$2}" > "$2" && git add "$2" \
    && git commit -q -m "add $2" && git rev-parse HEAD )
}

# trusted <dir> - the pre-trust flag recorded for <dir> in .claude.json, or "unset".
trusted() { jq -r --arg p "$1" '.projects[$p].hasTrustDialogAccepted // "unset"' "$CLAUDE_CONFIG_DIR/.claude.json"; }

# chief_add_origin <repo> <branch> - a bare $BATS_TEST_TMPDIR/origin.git ($BARE)
# as <repo>'s origin, with <branch> pushed.
chief_add_origin() {
  BARE="$BATS_TEST_TMPDIR/origin.git"
  git init -q --bare -b "$2" "$BARE"
  git -C "$1" remote add origin "$BARE"
  git -C "$1" push -q origin "$2"
}
# project_with_origin <dir> - <dir> on main tracking an origin that a second
# clone ($BATS_TEST_TMPDIR/other) has advanced by from-origin.txt since.
project_with_origin() {
  local other="$BATS_TEST_TMPDIR/other"
  git init -q -b main "$1"
  git -C "$1" commit --allow-empty -q -m init
  chief_add_origin "$1" main
  git clone -q "$BARE" "$other"
  echo new > "$other/from-origin.txt"
  git -C "$other" add . && git -C "$other" commit -q -m "advance origin" && git -C "$other" push -q origin main
}

# herdr_fault <call> <times> <before|after> <exit code> <stdout> - from now on
# `herdr <call>` is faulted the first <times> times (see fixtures/faulty/herdr);
# every other call runs the real herdr.
herdr_fault() {
  export HERDR_REAL="${HERDR_REAL:-$(command -v herdr)}" HERDR_FAULTS="$BATS_TEST_TMPDIR/faults"
  case ":$PATH:" in *":$TEST_DIR/fixtures/faulty:"*) ;; *) PATH="$TEST_DIR/fixtures/faulty:$PATH" ;; esac
  printf '%s|%s|%s|%s|%s\n' "$@" >> "$HERDR_FAULTS"
}

# watch_silent - the watcher keeps waiting: no output, killed by timeout (124)
watch_silent() {
  run env CHIEF_POLL=0.5 timeout 2 "$BIN/chief-watch.sh"
  assert_equal "$status:$output" "124:"
}
watch_once() { run env CHIEF_POLL=1 timeout 10 "$BIN/chief-watch.sh"; }

# standin_turns <id> - every turn the stand-in in that task's worktree received.
standin_turns() { cat "$STANDIN_DIR/$1.log" 2>/dev/null; }
# standin_keys <id> - the lone special keys (esc) the stand-in received.
standin_keys() { cat "$STANDIN_DIR/$1.keys" 2>/dev/null; }
# standin_mode <id> <mode>... - modes for the stand-in the next spawn of <id> starts.
standin_mode() { local id=$1; shift; printf '%s\n' "$@" > "$STANDIN_DIR/modes/$id"; }
# standin_never_ready <id> - the next spawn of <id> fails: its TUI never renders,
# and herdr gives up on the pane after 5 s instead of 30.
standin_never_ready() { standin_mode "$1" never-ready; export CHIEF_HERDR_AGENT_START_TIMEOUT_MS=5000; }
# standin_hold <id> / standin_release <id> - keep the turn `working` / let it finish.
standin_hold() { : > "$STANDIN_DIR/hold/$1"; }
standin_release() { rm -f "$STANDIN_DIR/hold/$1"; }
# standin_type <id> <text> - types <text> into the agent's input line, no Enter.
standin_type() {
  herdr pane send-text "$(sed -n 's/^endpoint=herdr://p' "$CHIEF_HOME/tasks/$1/meta")" "$2" >/dev/null
}

# wait_settled <id> - waits for the agent's current turn (the brief) to finish.
wait_settled() {
  settled() { ! herdr agent get "$1" | jq -e '.result.agent.agent_status == "working"' >/dev/null; }
  eventually 20 settled "$1"
}

# eventually <secs> <cmd...> - retries <cmd> until it passes; real backends
# deliver mid-task sends and finish turns asynchronously. Never use a bare sleep.
# <cmd> must be a function or command: "$(...)" in its arguments expands once,
# before the first try, and a late change never passes.
eventually() {
  local secs=$1 i; shift
  for i in $(seq 1 $((secs * 4))); do "$@" >/dev/null 2>&1 && return 0; sleep 0.25; done
  "$@"
}

# assert_contains_all <text> <needle>... - fails naming the first missing needle.
assert_contains_all() {
  local text=$1 needle; shift
  for needle in "$@"; do [[ $text == *"$needle"* ]] || { echo "missing: $needle" >&2; return 1; }; done
}
# refute_contains_any <text> <needle>... - fails naming the first needle present.
refute_contains_any() {
  local text=$1 needle; shift
  for needle in "$@"; do [[ $text != *"$needle"* ]] || { echo "unexpected: $needle" >&2; return 1; }; done
}
# assert_agent_neutral <text> - the text never names Claude (CLAUDE.md aside).
assert_agent_neutral() {
  local text=${1//CLAUDE.md/}
  [[ ${text,,} != *claude* ]] || { echo "names claude" >&2; return 1; }
}
# assert_no_placeholders <text> - no template placeholder is left unfilled.
assert_no_placeholders() {
  local ph
  for ph in TASK SPEC BRANCH REPORT_FILE STATUS_FILE TURN_FILE INBOX_DIR TASK_ID; do
    [[ $1 != *"{$ph}"* ]] || { echo "unfilled {$ph}" >&2; return 1; }
  done
}
