# orca.bash - a real headless Orca for the .bats files, running the zero-cost
# stand-in agent (fixtures/standin/), never a paid CLI. `load lib/orca` after
# lib/common; call chief_orca_server from setup_file, chief_orca_stop from
# teardown_file. One server per file; its tests run serially.

# Pane PATH is the server's plus the login shell's (Orca hydrates it), so the
# stand-ins go first through the pane shell's rc, not the server's env.
_chief_orca_rc() {  # <home>
  printf 'PATH=%q:$PATH\n' "$STANDIN_BIN" > "$1/.bashrc"
  printf '[ -f ~/.bashrc ] && . ~/.bashrc\n' > "$1/.bash_profile"
}

# _chief_orca_app - the Orca launcher: `orca-ide` on PATH, else the CI/local install.
_chief_orca_app() {
  command -v orca-ide || { [ -x "$REPO_ROOT/tests/.cache/orca/squashfs-root/AppRun" ] && echo "$REPO_ROOT/tests/.cache/orca/squashfs-root/AppRun"; }
}

# chief_orca_require - skips the file without Orca and Xvfb, unless
# CHIEF_TEST_REQUIRE_BACKENDS=1 (CI), where that is a failure.
chief_orca_require() {
  [ -n "$(_chief_orca_app)" ] && command -v Xvfb > /dev/null && return 0
  [ "${CHIEF_TEST_REQUIRE_BACKENDS:-}" != 1 ] || { echo "orca/Xvfb missing but required" >&2; return 1; }
  skip "orca/Xvfb not installed (tests/chief/ci/install-orca.sh)"
}

# chief_orca_server - Xvfb plus `orca-ide serve` with own HOME/XDG/TMPDIR/port,
# a scrubbed env and SHELL=bash. Exports HOME, XDG_CONFIG_HOME, TMPDIR, STANDIN_DIR and
# PATH (with the `orca` CLI the server installs into its HOME) for the file.
chief_orca_server() {
  local d i app
  app=$(_chief_orca_app)
  d=$(mktemp -d "${TMPDIR:-/tmp}/cho.XXXX")
  echo "$d" > "$BATS_FILE_TMPDIR/orca-dir"
  echo "$d" >> "$BATS_SUITE_TMPDIR/orcas"  # for setup_suite's teardown_suite sweep
  mkdir -p "$d/home" "$d/tmp" "$d/standin/modes" "$d/standin/hold"
  _chief_orca_rc "$d/home"
  ( cd "$d" && Xvfb -displayfd 9 -screen 0 1280x1024x24 -nolisten tcp 9> "$d/display" > "$d/xvfb.log" 2>&1 < /dev/null 3>&- &
    echo $! > "$d/xvfb.pid" )
  for i in $(seq 1 100); do [ -s "$d/display" ] && break; sleep 0.1; done
  [ -s "$d/display" ] || { echo "Xvfb did not come up" >&2; return 1; }
  ( cd "$d" && env -i HOME="$d/home" XDG_CONFIG_HOME="$d/home/.config" SHELL=/bin/bash TERM=xterm-256color TMPDIR="$d/tmp" AGENT_BROWSER_SOCKET_DIR="$d/tmp" ELECTRON_DISABLE_SANDBOX=1 \
      PATH="/usr/bin:/bin" DISPLAY=":$(cat "$d/display")" LIBGL_ALWAYS_SOFTWARE=1 \
      STANDIN_DIR="$d/standin" STANDIN_TURN_SECS="${STANDIN_TURN_SECS:-1}" \
      GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
      nohup "$app" serve --port 0 --pairing-address 127.0.0.1 --json > "$d/serve.log" 2>&1 < /dev/null 3>&- &
    echo $! > "$d/pid" )
  for i in $(seq 1 300); do grep -q orca_server_ready "$d/serve.log" 2>/dev/null && break; sleep 0.1; done
  grep -q orca_server_ready "$d/serve.log" || { echo "orca serve did not come up" >&2; return 1; }
  export HOME="$d/home" XDG_CONFIG_HOME="$d/home/.config" TMPDIR="$d/tmp" STANDIN_DIR="$d/standin"
  PATH="$d/home/.local/bin:$PATH"
  orca status --json 2>/dev/null | jq -e '.ok == true' > /dev/null
}

# _chief_orca_pids <dir> - every process running in <dir>: the server and its
# Chromium helpers, Xvfb, the pty daemon (which outlives the server, with the
# panes) and the stand-ins in the panes.
_chief_orca_pids() {
  local p cwd
  for p in /proc/[0-9]*; do
    cwd=$(readlink "$p/cwd" 2>/dev/null) || continue
    cwd=${cwd% (deleted)}
    case "$cwd" in "$1"|"$1"/*) echo "${p#/proc/}" ;; esac
  done
}

# _chief_orca_reap <dir> - kills them all, escalating to KILL.
_chief_orca_reap() {
  local sig i
  for sig in TERM KILL; do
    _chief_orca_pids "$1" | xargs -r kill "-$sig" 2>/dev/null
    for i in $(seq 1 30); do [ -z "$(_chief_orca_pids "$1")" ] && return 0; sleep 0.1; done
  done
  return 1
}

# chief_orca_stop - stops the file's server and everything it started.
chief_orca_stop() {
  local d rc=0
  d=$(cat "$BATS_FILE_TMPDIR/orca-dir" 2>/dev/null) || return 0
  _chief_orca_reap "$d" || { echo "orca processes in $d survived KILL" >&2; rc=1; }
  rm -rf "$d"
  return $rc
}
