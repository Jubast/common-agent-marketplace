# hc.bash - a real herdr-core (`hc`) per test, running the zero-cost stand-in
# agent (fixtures/standin/), never a paid CLI. `load ../lib/hc` after lib/common;
# call chief_hc_server from the test's setup, chief_hc_stop from teardown.

# chief_hc_require - skips the test without hc, unless CHIEF_TEST_REQUIRE_BACKENDS=1
# (CI), where that is a failure.
chief_hc_require() {
  command -v hc > /dev/null && return 0
  [ "${CHIEF_TEST_REQUIRE_BACKENDS:-}" != 1 ] || { echo "hc missing but required" >&2; return 1; }
  skip "hc not installed (tests/chief/ci/install-hc.sh)"
}

# _chief_hc_env <dir> - points hc at the core whose files live in <dir>. Short
# paths: the socket path is capped at 107 bytes.
_chief_hc_env() {
  export HC_SESSION=chief-test XDG_CONFIG_HOME="$1/xc" XDG_RUNTIME_DIR="$1/xr" \
         XDG_STATE_HOME="$1/xs" XDG_DATA_HOME="$1/xd"
}

# chief_hc_server - starts this test's own core, and points the test's `hc` at it.
# Terminals inherit the CORE's env, so it gets a scrubbed one: a PATH whose only
# agent CLIs are the stand-ins, STANDIN_DIR, no HC_TERMINAL_ID.
chief_hc_server() {
  local d server_path
  chief_hc_require || return 1
  server_path="$STANDIN_BIN:$(dirname "$(command -v hc)"):$(dirname "$(command -v jq)"):/usr/bin:/bin"
  chief_zero_cost_guard "$server_path" || return 1
  d=$(mktemp -d "${TMPDIR:-/tmp}/chc.XXXX")
  echo "$d" > "$BATS_TEST_TMPDIR/hc-dir"
  echo "$d $STANDIN_DIR" >> "$BATS_SUITE_TMPDIR/hcs"  # for setup_suite's teardown_suite sweep
  mkdir -p "$d/home" "$d/xc" "$d/xr" "$d/xs" "$d/xd"
  chmod 700 "$d/xr"
  _chief_hc_env "$d"
  ( cd "$d" && env -i HOME="$d/home" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
      XDG_STATE_HOME="$XDG_STATE_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" HC_SESSION="$HC_SESSION" \
      PATH="$server_path" TERM=xterm-256color \
      STANDIN_DIR="$STANDIN_DIR" STANDIN_TURN_SECS="${STANDIN_TURN_SECS:-1}" \
      GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
      hc server start --json > "$d/server.json" 2> "$d/server.log" < /dev/null )
  jq -e '.pid' "$d/server.json" > "$d/pid" || { echo "hc core did not come up" >&2; cat "$d/server.log" >&2; return 1; }
}

# chief_hc_stop - stops this test's core; fails if it or a stand-in outlives it.
chief_hc_stop() {
  local d pid f rc=0
  d=$(cat "$BATS_TEST_TMPDIR/hc-dir" 2>/dev/null) || return 0
  hc server stop >/dev/null 2>&1
  pid=$(cat "$d/pid")
  for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo "hc core $pid outlived 'server stop'" >&2; rc=1; fi
  sleep 0.2
  for f in "$STANDIN_DIR"/*.pid; do
    [ -e "$f" ] || continue
    if kill -0 "$(cat "$f")" 2>/dev/null; then kill "$(cat "$f")"; echo "stand-in $(cat "$f") outlived its core" >&2; rc=1; fi
  done
  [ -n "${BATS_TEST_COMPLETED:-}" ] || tail -n 20 "$d/server.log" "$XDG_STATE_HOME/herdr-core/$HC_SESSION/core.log" >&2
  rm -rf "$d"
  return $rc
}

# chief_hc_reap <dir> <standin-dir> - setup_suite's sweep of a leaked core.
chief_hc_reap() {
  local f
  ( _chief_hc_env "$1"; hc server stop >/dev/null 2>&1 )
  kill "$(cat "$1/pid" 2>/dev/null)" 2>/dev/null
  for f in "$2"/*.pid; do [ -e "$f" ] && kill "$(cat "$f")" 2>/dev/null; done
  rm -rf "$1"
}
