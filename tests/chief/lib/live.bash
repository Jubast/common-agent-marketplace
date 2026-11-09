# live.bash - helpers for live/*.bats: real agent CLIs, real tokens, nothing
# of the operator's. `load ../lib/live` then `load ../lib/common` (in this order:
# common scrubs the caller's herdr sockets, which live records first) from
# setup_file, setup and teardown_file. A file gates itself (live_gate), checks its tools
# (live_require), then live_isolate builds the scratch world: own HOME/XDG, own
# herdr server and socket, own CLAUDE_CONFIG_DIR/CODEX_HOME/COPILOT_HOME, proven
# not to be the operator's before anything runs. Only login files are copied in.
# The tests of a file run in order and may share the agents they start.

# The caller's herdr sockets, recorded before lib/common scrubs them.
LIVE_CALLER_SOCKS=("${HERDR_SOCKET_PATH:-}" "${HERDR_CLIENT_SOCKET_PATH:-}" "$HOME/.config/herdr/herdr.sock"
                   "$HOME/.config/herdr/herdr-client.sock" "${XDG_CONFIG_HOME:-$HOME/.config}/herdr/herdr.sock")
LIVE_REAL_HOME=$HOME
LIVE_REAL_CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
LIVE_REAL_CODEX_HOME=${CODEX_HOME:-$HOME/.codex}
LIVE_REAL_COPILOT_HOME=${COPILOT_HOME:-$HOME/.copilot}
# The operator's Chief home, which no live test may touch (resolved as chief-*.sh would from here).
LIVE_REAL_CHIEF_HOME=${CHIEF_HOME:-$(. "$(dirname "${BASH_SOURCE[0]}")/../../../plugins/chief/bin/lib/home.sh" && cd "$(dirname "${BASH_SOURCE[0]}")" && chief_default_home)}

# live_gate <VAR> <what> - skips the file unless VAR=1: it spends real tokens.
live_gate() { [ "${!1:-0}" = 1 ] || skip "opt in with $1=1: $2 spends real tokens"; }

# live_require <cli>... - skips the file when a tool is missing.
live_require() {
  local cli
  for cli in "$@"; do command -v "$cli" > /dev/null || skip "$cli not on PATH"; done
}

# live_scrub - nothing from the caller's agent or herdr environment reaches the
# tests; a claude token (env login) is kept.
live_scrub() {
  local v
  for v in $(compgen -e | grep -E '^(HERDR_|CLAUDE|CODEX_|COPILOT_|ORCA_|XDG_|TMUX)' | grep -v '^CLAUDE_CODE_OAUTH_TOKEN$'); do
    unset "$v"
  done
}

# live_env - the scratch environment, for setup() (lib/common resets some of it).
live_env() {
  LIVE=$(cat "$BATS_FILE_TMPDIR/live-iso")
  live_scrub
  . "$LIVE/env.sh"
  LIVE_REAL_CHIEF_HOME=$(cat "$LIVE/real-chief-home")
}

# live_login_claude / _codex / _copilot - copy only the login into the scratch
# homes, plus the seeds that skip first-run screens. Non-zero: no login.
live_login_claude() {
  mkdir -p "$CLAUDE_CONFIG_DIR"
  if [ -z "${ANTHROPIC_API_KEY:-}${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    [ -f "$LIVE_REAL_CLAUDE_DIR/.credentials.json" ] || return 1
    ( umask 077; cp "$LIVE_REAL_CLAUDE_DIR/.credentials.json" "$CLAUDE_CONFIG_DIR/.credentials.json" )
  fi
  echo '{"hasCompletedOnboarding":true}' > "$CLAUDE_CONFIG_DIR/.claude.json"
  echo '{"skipDangerousModePermissionPrompt":true}' > "$CLAUDE_CONFIG_DIR/settings.json"
}
live_login_codex() {  # <trusted dir>...
  local d
  [ -f "$LIVE_REAL_CODEX_HOME/auth.json" ] || return 1
  mkdir -p "$CODEX_HOME"
  ( umask 077; cp "$LIVE_REAL_CODEX_HOME/auth.json" "$CODEX_HOME/auth.json" )
  { echo 'check_for_update_on_startup = false'; printf '\n[features]\nhooks = true\n'
    for d in "$@"; do printf '\n[projects."%s"]\ntrust_level = "trusted"\n' "$d"; done; } > "$CODEX_HOME/config.toml"
}
live_login_copilot() {  # <trusted dir>...
  grep -q '"authTokens"' "$LIVE_REAL_COPILOT_HOME/config.json" 2>/dev/null || return 1
  mkdir -p "$COPILOT_HOME"
  ( umask 077
    grep -v '^[[:space:]]*//' "$LIVE_REAL_COPILOT_HOME/config.json" \
      | jq --args '. + {trustedFolders: $ARGS.positional}' "$@" > "$COPILOT_HOME/config.json" )
}

# live_isolate - the scratch world and its own herdr server. Leaves $LIVE set
# for the file; call it from setup_file after live_require.
live_isolate() {
  local v
  LIVE=$(mktemp -d /tmp/chl.XXXXXX)  # short: the socket path is capped at 107 bytes
  echo "$LIVE" > "$BATS_FILE_TMPDIR/live-iso"
  echo "$LIVE_REAL_CHIEF_HOME" > "$LIVE/real-chief-home"  # per-test loads of this file see the scratch env
  echo "$LIVE" >> "$BATS_SUITE_TMPDIR/lives"  # for setup_suite's teardown_suite sweep
  mkdir -p "$LIVE/home" "$LIVE/xdg-config" "$LIVE/xdg-run" "$LIVE/xdg-data"
  chmod 700 "$LIVE" "$LIVE/xdg-run"
  {
    printf 'export LIVE=%q HOME=%q XDG_CONFIG_HOME=%q XDG_RUNTIME_DIR=%q XDG_DATA_HOME=%q\n' \
      "$LIVE" "$LIVE/home" "$LIVE/xdg-config" "$LIVE/xdg-run" "$LIVE/xdg-data"
    printf 'export HERDR_SOCKET_PATH=%q CLAUDE_CONFIG_DIR=%q CODEX_HOME=%q COPILOT_HOME=%q\n' \
      "$LIVE/xdg-run/herdr.sock" "$LIVE/claude-config" "$LIVE/codex-home" "$LIVE/copilot-home"
    printf 'export CHIEF_HOME=%q\n' "$LIVE/ws/.chief"  # whatever cwd a model runs chief-*.sh from
    printf 'export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t CHIEF_POLL=3\n'
    for v in ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN; do
      [ -z "${!v:-}" ] || printf 'export %s=%q\n' "$v" "${!v}"
    done
  } > "$LIVE/env.sh"
  live_env
  live_guard && live_herdr_server
}

# live_guard - proves the herdr to be started is not the caller's, before any
# herdr client call.
live_guard() {
  local forbidden sock=$HERDR_SOCKET_PATH
  case $sock in "$LIVE"/*) ;; *) echo "live_guard: socket is outside the scratch dir" >&2; return 1 ;; esac
  for forbidden in $(printf '%s\n' "${LIVE_CALLER_SOCKS[@]}" | sort -u); do
    [ -z "$forbidden" ] && continue
    [ "$(realpath -m "$sock")" != "$(realpath -m "$forbidden")" ] || { echo "live_guard: socket equals $forbidden" >&2; return 1; }
  done
  [ ! -e "$sock" ] || { echo "live_guard: socket already exists" >&2; return 1; }
  live_guard_chief_home
}
# live_guard_chief_home - CHIEF_HOME (and so the backlog) is inside the scratch
# dir and is not the operator's.
live_guard_chief_home() {
  case $CHIEF_HOME in "$LIVE"/*) ;; *) echo "live_guard: CHIEF_HOME $CHIEF_HOME is outside the scratch dir" >&2; return 1 ;; esac
  case "$CHIEF_HOME/" in "$LIVE_REAL_CHIEF_HOME"/*) echo "live_guard: CHIEF_HOME is the operator's" >&2; return 1 ;; esac
  case "$LIVE_REAL_CHIEF_HOME/" in "$LIVE"/*) echo "live_guard: the operator's Chief home is inside the scratch dir" >&2; return 1 ;; esac
}

# live_herdr_server - the file's own headless herdr; panes inherit this env.
live_herdr_server() {
  local i pid default_owner own_owner listing
  default_owner=$(live_sock_owner "$LIVE_REAL_HOME/.config/herdr/herdr.sock")
  ( cd "$LIVE" && nohup herdr server > "$LIVE/server.log" 2>&1 < /dev/null & echo $! > "$LIVE/server.pid" )
  pid=$(cat "$LIVE/server.pid")
  for i in $(seq 1 40); do [ -S "$HERDR_SOCKET_PATH" ] && break; sleep 0.25; done
  [ -S "$HERDR_SOCKET_PATH" ] || { echo "live_guard: own herdr did not come up" >&2; return 1; }
  own_owner=$(live_sock_owner "$HERDR_SOCKET_PATH")
  [ "$own_owner" = "$pid" ] || [ "$(ps -o ppid= -p "$own_owner" | tr -d ' ')" = "$pid" ] || { echo "live_guard: socket owned by '$own_owner', not the server started here ($pid)" >&2; return 1; }
  [ "$own_owner" != "$default_owner" ] || { echo "live_guard: server pid equals the default server's" >&2; return 1; }
  listing=$(herdr workspace list 2>&1)
  [ "$(jq -r '.result.workspaces | length' <<< "$listing")" = 0 ] || { echo "live_guard: own server's workspace list is not empty" >&2; return 1; }
}
live_sock_owner() { ss -xlpH 2>/dev/null | awk -v s="$1" '$5 == s' | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2; }

# live_stop - teardown_file: the server, whatever it left running (a Codex
# app-server daemon, agents), and the scratch dir with the copied logins.
live_stop() {
  LIVE=$(cat "$BATS_FILE_TMPDIR/live-iso" 2>/dev/null) || return 0
  live_env
  [ ! -d "$CODEX_HOME" ] || ! command -v codex > /dev/null || codex app-server daemon stop > /dev/null 2>&1 || true
  herdr server stop > /dev/null 2>&1 || true
  live_reap "$LIVE"
}
# live_reap <dir> - kills every process whose command line names <dir>, removes it.
live_reap() {
  local p
  for p in $(pgrep -f -- "$1" || true); do [ "$p" = $$ ] || kill "$p" 2>/dev/null || true; done
  sleep 0.5
  rm -rf "$1"
}

# --- panes -------------------------------------------------------------------

# live_pane <label> <cwd> <command...> - a workspace in the file's herdr running
# the command; prints the pane id.
live_pane() {
  local label=$1 cwd=$2 pane; shift 2
  pane=$(herdr workspace create --cwd "$cwd" --label "$label" --no-focus | jq -r '.result.root_pane.pane_id // empty')
  [ -n "$pane" ] || return 1
  herdr pane run "$pane" "$*" > /dev/null
  echo "$pane"
}
# live_screen <pane> - the pane's recent output, unwrapped, whitespace collapsed.
live_screen() { herdr pane read "$1" --source recent-unwrapped --lines 300 2>/dev/null | tr -s '[:space:]' ' '; }
# live_screen_has <pane> <ere>
live_screen_has() { live_screen "$1" | grep -Eq -- "$2"; }
# live_visible_has <pane> <ere> - the pane's current screen only, not its history.
live_visible_has() { herdr pane read "$1" --source visible --lines 80 2>/dev/null | tr -s '[:space:]' ' ' | grep -Eq -- "$2"; }
live_visible_gone() { ! live_visible_has "$@"; }
# live_wait <secs> <check> <pane> [args] - polls the check until it passes; on a
# timeout prints the pane's tail.
live_wait() {
  local secs=$1; shift
  eventually "$secs" "$@" && return 0
  echo "timed out waiting for: $*; screen tail:" >&2
  herdr pane read "$2" --source recent-unwrapped --lines 40 >&2
  return 1
}
# live_say <pane> <text> - types the text and presses Enter.
live_say() { herdr pane send-text "$1" "$2" > /dev/null; sleep 1; herdr pane send-keys "$1" Enter > /dev/null; }

# --- Chief on a harness ------------------------------------------------------

# live_chief_workspace - $LIVE/ws (a git repo, the Chief session's dir) with a
# project at $LIVE/ws/proj holding NOTE.txt, Chief set up on herdr and
# workers on claude:haiku. The token never appears in a prompt, only in a worker's report.
live_chief_workspace() {
  LIVE_TOKEN=zebra-$RANDOM$RANDOM
  mkdir -p "$LIVE/ws/proj"
  git -C "$LIVE/ws" init -q -b main
  printf '.chief/\nproj/\n' > "$LIVE/ws/.gitignore"
  git -C "$LIVE/ws" add . && git -C "$LIVE/ws" commit -q -m init
  git -C "$LIVE/ws/proj" init -q -b main
  echo "$LIVE_TOKEN" > "$LIVE/ws/proj/NOTE.txt"
  git -C "$LIVE/ws/proj" add . && git -C "$LIVE/ws/proj" commit -q -m init
  ( cd "$LIVE/ws" && CHIEF_HOME="$LIVE/ws/.chief" "$BIN/chief-setup.sh" --backend herdr > /dev/null )
  echo "claude:haiku" > "$LIVE/ws/.chief/config/agents"
  echo "$LIVE_TOKEN" > "$LIVE/token"
  # from the session's dir, chief-*.sh find the scratch home, not a real one
  [ "$(cd "$LIVE/ws" && env -u CHIEF_HOME bash -c ". '$BIN/lib/home.sh'; chief_default_home")" = "$LIVE/ws/.chief" ]
}
# live_dispatch_prompt <id> [gate file] - asks Chief to spawn a researcher that reads
# the token, once the gate file exists if one is given.
live_dispatch_prompt() {
  printf "Via the dispatch skill: file a backlog item %s and spawn it as a researcher on the project at %s/proj; its only job is to %sread NOTE.txt in the project and report its content (one line). Wait in the foreground until chief-spawn prints 'spawned:', then say so and stop; do not poll afterwards." "$1" "$LIVE/ws" "${2:+wait until the file $2 exists (check with ls every few seconds), then }"
}
# live_task_status_is <id> <prefix> - the last status line of a Chief task starts so.
live_task_status_is() { [[ $(tail -n 1 "$LIVE/ws/.chief/tasks/$1/status" 2>/dev/null) == "$2"* ]]; }
# live_chief_identity <pane> - asks without tools and waits for the answer.
live_chief_identity() {
  live_say "$1" "Without using any tool: what is your name in this workspace? Reply with exactly NAME=<name>."
  live_wait 120 live_screen_has "$1" 'NAME=[A-Za-z]'
}
# live_wait_seen <pane> <secs> <ere>... - polls until each <ere> has shown on the
# screen at some poll (a long conversation scrolls early lines away, so they
# need not be on it together); on a timeout prints what was missing.
live_wait_seen() {
  local pane=$1 secs=$2 i e k n; shift 2
  local -a seen=()
  for i in $(seq 1 $((secs * 2))); do
    n=0 k=0
    for e in "$@"; do
      [ -n "${seen[k]:-}" ] || ! live_screen_has "$pane" "$e" || seen[k]=1
      [ -z "${seen[k]:-}" ] || n=$((n + 1))
      k=$((k + 1))
    done
    [ "$n" -lt "$#" ] || return 0
    sleep 0.5
  done
  echo "seen $n of $# patterns; screen tail:" >&2
  herdr pane read "$pane" --source recent-unwrapped --lines 40 >&2
  return 1
}
# live_dispatch_and_wake <pane> <id> <ere> - asks Chief to spawn a researcher
# and waits for <ere> (what the wake looks like on this CLI) and for the
# worker's report token: Chief was told not to poll, so it can only have
# learned of the report from the wake.
live_dispatch_and_wake() {
  live_say "$1" "$(live_dispatch_prompt "$2")"
  live_wait_seen "$1" 420 "$3" "$(cat "$LIVE/token")" || { live_watchers >&2; return 1; }
  live_task_status_is "$2" 'done:'
}
# live_watchers - the Chief watcher processes and state of the scratch world, for a failure report.
live_watchers() {
  echo "watchers:"; pgrep -af -- "(stop-watch|watch-reason|chief-watch)" | grep -v pgrep | cut -c1-160
  echo "state:"; ls -l "$CHIEF_HOME/state" 2>&1
}
# live_quit_tui <pane> <ere> - Ctrl-C twice, repeated, until the screen shows <ere> (the exit text).
live_quit_tui() {
  local i
  for i in 1 2 3 4 5; do
    herdr pane send-keys "$1" C-c > /dev/null
    sleep 1
    herdr pane send-keys "$1" C-c > /dev/null
    eventually 3 live_exited "$1" "$2" && return 0
  done
  echo "the TUI did not show /$2/; visible screen:" >&2
  herdr pane read "$1" --source visible --lines 40 >&2
  return 1
}
live_exited() { live_visible_has "$@" || live_screen_has "$@"; }
