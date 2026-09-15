#!/usr/bin/env bash
# chief-watch.sh - the token saver. A plain bash loop, no model calls: sleeps,
# checks every in-flight task's state, and only exits (with a reason printed
# on stdout) when something needs the operator's attention. Chief's Stop hook
# runs this in the background at zero model cost and only "rewakes" you when
# it exits - see hooks/session-stop.sh.
#
# Usage: chief-watch.sh   (runs until something actionable happens, or forever)
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"
. "$CHIEF_ROOT/bin/lib/chief-backend.sh"

POLL="${CHIEF_POLL:-15}"
BEACON="$STATE/.last-watcher-beat"

in_flight_ids() {
  local f id
  for f in "$STATE"/*.meta; do
    [ -e "$f" ] || continue
    id=$(basename "$f" .meta)
    [ "$(chief_meta_get "$id" status)" = "working" ] && printf '%s\n' "$id"
  done
}

while true; do
  touch "$BEACON"

  any_in_flight=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    any_in_flight=1
    line=$("$CHIEF_ROOT/bin/chief-crew-state.sh" "$id" 2>/dev/null) || continue
    case "$line" in
      "state: done"*|"state: failed"*|"state: blocked"*|"state: needs-decision"*|"state: stale"*)
        echo "$id: $line"
        exit 0
        ;;
    esac
  done < <(in_flight_ids)

  if [ "$any_in_flight" -eq 0 ]; then
    echo "nothing in flight"
    exit 0
  fi

  sleep "$POLL"
done
