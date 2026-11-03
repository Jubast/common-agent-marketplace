# setup_suite - runs once per bats run (tests/chief).
setup_suite() {
  local repo cli
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  [ ! -d "$repo/tests/.cache/bin" ] || export PATH="$repo/tests/.cache/bin:$PATH"
  for cli in git jq; do command -v "$cli" >/dev/null || { echo "setup_suite: $cli is required" >&2; return 1; }; done
  command -v herdr >/dev/null || { echo "setup_suite: herdr not found; run tests/chief/ci/install-herdr.sh" >&2; return 1; }
}

# teardown_suite - a server or temp dir still around is a leak (a skipped
# teardown); kill it and fail. Servers are logged by chief_herdr_server.
teardown_suite() {
  local d standin f leaked=0
  [ -f "$BATS_SUITE_TMPDIR/servers" ] || return 0
  while read -r d standin; do
    [ -d "$d" ] || continue
    leaked=$((leaked + 1))
    HERDR_SOCKET_PATH="$d/xr/h.sock" herdr server stop >/dev/null 2>&1
    kill "$(cat "$d/pid" 2>/dev/null)" 2>/dev/null
    for f in "$standin"/*.pid; do [ -e "$f" ] && kill "$(cat "$f")" 2>/dev/null; done
    rm -rf "$d"
  done < "$BATS_SUITE_TMPDIR/servers"
  [ "$leaked" -eq 0 ] || { echo "teardown_suite: $leaked herdr server(s) outlived their test" >&2; return 1; }
}
