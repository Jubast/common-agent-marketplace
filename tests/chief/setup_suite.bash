# setup_suite - runs once per bats run (tests/chief).
setup_suite() {
  local repo cli
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  [ ! -d "$repo/tests/.cache/bin" ] || export PATH="$repo/tests/.cache/bin:$PATH"
  for cli in git jq; do command -v "$cli" >/dev/null || { echo "setup_suite: $cli is required" >&2; return 1; }; done
}

# teardown_suite - a server or temp dir still around is a leak (a skipped
# teardown); kill it and fail. Servers are logged by chief_herdr_server,
# chief_hc_server and chief_orca_server.
teardown_suite() {
  local d standin f leaked=0
  if [ -f "$BATS_SUITE_TMPDIR/orcas" ]; then
    . "$(dirname "${BASH_SOURCE[0]}")/lib/orca.bash"
    while read -r d; do
      [ -d "$d" ] || continue
      leaked=$((leaked + 1)); _chief_orca_reap "$d"; rm -rf "$d"
    done < "$BATS_SUITE_TMPDIR/orcas"
  fi
  if [ -f "$BATS_SUITE_TMPDIR/hcs" ]; then
    . "$(dirname "${BASH_SOURCE[0]}")/lib/hc.bash"
    while read -r d standin; do
      [ -d "$d" ] || continue
      leaked=$((leaked + 1)); chief_hc_reap "$d" "$standin"
    done < "$BATS_SUITE_TMPDIR/hcs"
  fi
  if [ -f "$BATS_SUITE_TMPDIR/servers" ]; then
    while read -r d standin; do
      [ -d "$d" ] || continue
      leaked=$((leaked + 1))
      HERDR_SOCKET_PATH="$d/xr/h.sock" herdr server stop >/dev/null 2>&1
      kill "$(cat "$d/pid" 2>/dev/null)" 2>/dev/null
      for f in "$standin"/*.pid; do [ -e "$f" ] && kill "$(cat "$f")" 2>/dev/null; done
      rm -rf "$d"
    done < "$BATS_SUITE_TMPDIR/servers"
  fi
  if [ -f "$BATS_SUITE_TMPDIR/lives" ]; then
    . "$(dirname "${BASH_SOURCE[0]}")/lib/live.bash"
    while read -r d; do
      [ -d "$d" ] || continue
      leaked=$((leaked + 1))
      HERDR_SOCKET_PATH="$d/xdg-run/herdr.sock" herdr server stop >/dev/null 2>&1
      live_reap "$d"
    done < "$BATS_SUITE_TMPDIR/lives"
  fi
  [ "$leaked" -eq 0 ] || { echo "teardown_suite: $leaked server(s) outlived their test" >&2; return 1; }
}
