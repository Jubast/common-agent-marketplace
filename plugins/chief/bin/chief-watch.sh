#!/usr/bin/env bash
# chief-watch.sh - the token saver. A plain bash loop, no model calls: sleeps,
# checks every in-flight task's state, and only exits (with a reason printed
# on stdout) when something needs the operator's attention. Chief's Stop hook
# runs this in the background at zero model cost and only "rewakes" you when
# it exits - see hooks/stop-watch-arm.sh.
#
# Usage: chief-watch.sh   (runs until something actionable happens, or forever)
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/paths.sh"
chief_ensure_dirs
. "$CHIEF_ROOT/bin/lib/meta.sh"
. "$CHIEF_ROOT/bin/lib/backends/backend.sh"

POLL="${CHIEF_POLL:-15}"
BEACON="$STATE/.last-watcher-beat"

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

# round_gate <reviewer-id> - for a reviewer with siblings, returns 1 (stay quiet)
# until every live reviewer of its builder is done. The last one writes the
# round's combined report, acknowledges every reviewer's done line (so none
# is announced again) and sets ROUND_NOTE to point at the report. A sibling
# that failed, blocked or went stale announces itself; it holds the round back.
ROUND_NOTE=""
round_gate() {
  local bid rid live="" n out line ids
  bid=$(chief_meta_get "$1" for 2>/dev/null) || return 0
  for rid in $(chief_meta_get "$bid" reviewer 2>/dev/null); do
    [ "$(chief_meta_get "$rid" status 2>/dev/null)" != torn-down ] || continue
    live+="${live:+ }$rid"
  done
  [[ $live == *" "* ]] || return 0
  for rid in $live; do
    [[ $("$CHIEF_ROOT/bin/task/chief-crew-state.sh" "$rid" 2>/dev/null) == "state: done"* ]] || return 1
  done
  n=$(chief_meta_get "$bid" review_round 2>/dev/null || echo 1)
  out=$(chief_task_path "$bid" "review-round-$n.md")
  {
    echo "# Review round $n of $bid"
    for rid in $live; do
      printf '\n## %s\n\n' "$rid"
      cat "$(chief_task_path "$rid" report.md)" 2>/dev/null || echo "(no report)"
    done
  } > "$out"
  for rid in $live; do
    line=$("$CHIEF_ROOT/bin/task/chief-crew-state.sh" "$rid" 2>/dev/null) || continue
    chief_meta_set "$rid" notify-baseline "$(chief_notify_line "$line")"
  done
  read -ra ids <<< "$live"
  ROUND_NOTE=" · all ${#ids[@]} reviewers of $bid done, combined report: $out"
}

while true; do
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
        [ "$norm" = "$baseline" ] && continue
        chief_meta_set "$id" notify-baseline "$norm"
        # One wake per round: a finished reviewer waits for its siblings.
        if [[ $line == "state: done"* ]]; then
          round_gate "$id" || { chief_meta_set "$id" notify-baseline ""; continue; }
        fi
        echo "$id: $line$ROUND_NOTE"
        exit 0
        ;;
      *)
        [ -n "$baseline" ] && chief_meta_set "$id" notify-baseline ""
        ;;
    esac
  done < <(in_flight_ids)

  if [ "$any_in_flight" -eq 0 ]; then
    echo "nothing in flight"
    exit 0
  fi

  sleep "$POLL"
done
