#!/usr/bin/env bash
# test-backlog.sh - chief-backlog.sh: the whole markdown-file backlog.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
BL="$REPO_ROOT/plugins/chief/bin/chief-backlog.sh"
. "$TEST_DIR/lib/harness.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" && git init -q
export CHIEF_HOME="$WORK/.chief"
BACKLOG="$CHIEF_HOME/data/backlog.md"

echo "test-backlog:"

assert_success "add files a new queued record" -- "$BL" add t-1 "Add rate limiting"
assert_success "add a second record" -- "$BL" add t-2 "Fix flaky test"
assert_contains "$("$BL" list)" "## t-1 [queued] Add rate limiting" "list shows the new record"
assert_eq "$("$BL" next)" "t-1" "next returns the first queued id"

assert_success "status moves a record to in-flight" -- "$BL" status t-1 in-flight
assert_contains "$("$BL" show t-1)" "[in-flight]" "show reflects the new status"
assert_eq "$("$BL" next)" "t-2" "next skips the now in-flight record"

assert_success "hold sets status and note together" -- "$BL" hold t-1 "blocked on captain - which limiter lib?"
assert_contains "$("$BL" show t-1)" "[held]" "hold sets status to held"
assert_contains "$("$BL" show t-1)" "note: blocked on captain" "hold records the reason"

assert_success "note overwrites the existing note, not appends" -- "$BL" note t-1 "operator said: token-bucket"
assert_contains "$(cat "$BACKLOG")" "note: operator said: token-bucket" "the new note text is present"
assert_not_contains "$(cat "$BACKLOG")" "blocked on captain" "the old note text is gone, not duplicated"
assert_eq "$(grep -c '^note:' "$BACKLOG")" "1" "exactly one note line exists for t-1"

assert_success "done marks a record done" -- "$BL" done t-2
assert_contains "$("$BL" list done)" "t-2" "list done filters correctly"
assert_eq "$("$BL" next)" "" "next returns nothing once no record is queued"

assert_failure "add refuses a duplicate id" -- "$BL" add t-1 "dup"
assert_failure "status refuses an unknown id" -- "$BL" status nope queued
assert_failure "status refuses an invalid status value" -- "$BL" status t-1 bogus
assert_failure "note refuses an unknown id" -- "$BL" note nope "x"
# NOTE: show does not validate the id - an unknown id just prints nothing
# (exit 0). Documenting actual behavior here, not asserting it's ideal.
assert_eq "$("$BL" show nope)" "" "show on an unknown id prints nothing rather than erroring"

harness_summary
