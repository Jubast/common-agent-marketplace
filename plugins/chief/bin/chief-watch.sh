#!/usr/bin/env bash
# chief-watch.sh - the token saver. A plain bash loop, no model calls: sleeps,
# checks every in-flight task's state, and only exits (with a reason printed
# on stdout) when something needs the operator's attention. Chief's Stop hook
# runs this in the background at zero model cost and only "rewakes" you when
# it exits - see hooks/stop-watch-arm.sh.
#
# One watcher per CHIEF_HOME: the newest owns state/watch.owner, an older one
# exits silently.
#
# Usage: chief-watch.sh   (runs until something actionable happens, or forever)
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/paths.sh"
chief_ensure_dirs
. "$CHIEF_ROOT/bin/lib/meta.sh"
. "$CHIEF_ROOT/bin/lib/backends/backend.sh"

POLL="${CHIEF_POLL:-15}"
BEACON="$STATE/.last-watcher-beat"
OWNER="$STATE/watch.owner"

is_owner() { [ "$(cat "$OWNER" 2>/dev/null || true)" = "$$" ]; }

echo $$ > "$OWNER.$$" && mv -f "$OWNER.$$" "$OWNER"

in_flight_ids() {
  local f id
  for f in "$TASKS"/*/meta; do
    [ -e "$f" ] || continue
    id=$(basename "$(dirname "$f")")
    case "$(chief_meta_get "$id" status)" in
      working|spawning) printf '%s\n' "$id" ;;
    esac
  done
}

# siblings_busy <id> - true while another reviewer of the same builder still
# works, so only the last one of a round wakes Chief; it acks the finished ones.
siblings_busy() {
  local bid rid line
  bid=$(chief_meta_get "$1" for 2>/dev/null) || return 1
  for rid in $(chief_meta_get "$bid" reviewer 2>/dev/null); do
    [ "$rid" != "$1" ] && [ "$(chief_meta_get "$rid" status 2>/dev/null)" = working ] || continue
    line=$("$CHIEF_ROOT/bin/task/chief-crew-state.sh" "$rid" 2>/dev/null) || continue
    case "$line" in
      "state: working"*) return 0 ;;
      "state: done"*) chief_meta_set "$rid" notify-baseline "$(chief_notify_line "$line")" ;;
    esac
  done
  return 1
}

while true; do
  is_owner || exit 0
  touch "$BEACON"

  any_in_flight=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    any_in_flight=1
    line=$("$CHIEF_ROOT/bin/task/chief-crew-state.sh" "$id" 2>/dev/null) || continue
    baseline=$(chief_meta_get "$id" notify-baseline 2>/dev/null || true)
    case "$line" in
      "state: done"*|"state: failed"*|"state: blocked"*|"state: needs-decision"*|"state: stale"*)
        # Notify once per state change: the delivered line is the baseline,
        # which a resumed held/done task also starts with (chief-backlog.sh).
        norm=$(chief_notify_line "$line")
        [ "$norm" = "$(chief_notify_line "$baseline")" ] && continue
        is_owner || exit 0
        chief_meta_set "$id" notify-baseline "$norm"
        [[ $line == "state: done"* ]] && siblings_busy "$id" && continue
        echo "$id: $line"
        exit 0
        ;;
      *)
        if [ -n "$baseline" ]; then is_owner || exit 0; chief_meta_set "$id" notify-baseline ""; fi
        ;;
    esac
  done < <(in_flight_ids)

  if [ "$any_in_flight" -eq 0 ]; then
    echo "nothing in flight"
    exit 0
  fi

  sleep "$POLL"
done
