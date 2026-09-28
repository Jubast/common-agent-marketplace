#!/usr/bin/env bash
# test-backend-herdr-mock.sh - zero-cost unit test of herdr.sh's
# agent_prompt_stalled recovery (_chief_herdr_prompt /
# _chief_herdr_prompt_box_empty), against a FAKE `herdr` CLI stub. No real
# herdr instance, no claude turn, no tokens.
#
# Not a substitute for test-backend-herdr.sh (the opt-in real-herdr
# integration test): this only proves the two stall scenarios (text never
# reached the input line vs. text landed but Enter didn't register) are
# told apart and recovered from the way they claim to be, against canned
# `herdr agent explain --json` output shaped like the real CLI's.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-backend-herdr-mock:"

if ! command -v jq >/dev/null 2>&1; then
  echo "  (skipped - jq not on PATH, required by backends/herdr.sh)"
  exit 0
fi

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/bin"

# --- fake `herdr` -------------------------------------------------------
# Logs every call to $HERDR_MOCK_LOG. `agent prompt` stalls
# $HERDR_MOCK_STALL_CALLS times (counted in $HERDR_MOCK_COUNT) before
# succeeding, so a test can make either the initial submission or a
# resend stall. `agent explain` reports the live prompt box's content per
# $HERDR_MOCK_BOX: "empty" (nothing landed), "has_text" (our text is
# sitting there), or "missing" (no live_prompt_box rule, the
# indeterminate case). `agent wait` fails when $HERDR_MOCK_WAIT_FAIL=1.
cat > "$WORK/bin/herdr" <<'FAKE_HERDR'
#!/usr/bin/env bash
echo "$*" >> "$HERDR_MOCK_LOG"
case "$1 $2" in
  "agent prompt")
    n=0
    [ -f "$HERDR_MOCK_COUNT" ] && n=$(cat "$HERDR_MOCK_COUNT")
    n=$((n + 1))
    echo "$n" > "$HERDR_MOCK_COUNT"
    if [ "$n" -le "${HERDR_MOCK_STALL_CALLS:-0}" ]; then
      echo '{"error":{"code":"agent_prompt_stalled"}}'
      exit 1
    fi
    exit 0
    ;;
  "agent explain")
    case "${HERDR_MOCK_BOX:-empty}" in
      empty)
        echo '{"evaluated_rules":[{"id":"live_prompt_box","evidence":{"region_preview":"❯\n"}}],"state":"idle"}'
        ;;
      has_text)
        echo '{"evaluated_rules":[{"id":"live_prompt_box","evidence":{"region_preview":"❯ do the fix\n"}}],"state":"idle"}'
        ;;
      missing)
        echo '{"evaluated_rules":[],"state":"working"}'
        ;;
    esac
    exit 0
    ;;
  "agent send-keys")
    exit 0
    ;;
  "agent wait")
    [ "${HERDR_MOCK_WAIT_FAIL:-0}" = "1" ] && exit 1
    exit 0
    ;;
  *)
    echo "fake-herdr: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
FAKE_HERDR
chmod +x "$WORK/bin/herdr"
export PATH="$WORK/bin:$PATH"
export HERDR_MOCK_LOG="$WORK/herdr.log"
export HERDR_MOCK_COUNT="$WORK/herdr.count"

. "$CHIEF_BIN/lib/backends/herdr.sh"

reset_mock() {
  : > "$HERDR_MOCK_LOG"
  rm -f "$HERDR_MOCK_COUNT"
}

# --- scenario 1: text never delivered - resend, no bare Enter -----------
reset_mock
HERDR_MOCK_STALL_CALLS=1 HERDR_MOCK_BOX=empty _chief_herdr_prompt t1 "do the fix"
assert_eq "$?" "0" "empty-box stall recovers by resending and succeeds"
assert_eq "$(grep -c '^agent prompt t1 do the fix' "$HERDR_MOCK_LOG")" "2" \
  "empty-box stall resends the same prompt text a second time"
assert_not_contains "$(cat "$HERDR_MOCK_LOG")" "agent send-keys" \
  "empty-box stall never sends a bare Enter (no submission to recover)"

# --- scenario 2: text landed, Enter didn't register - bare Enter only ---
reset_mock
HERDR_MOCK_STALL_CALLS=1 HERDR_MOCK_BOX=has_text _chief_herdr_prompt t2 "do the fix"
assert_eq "$?" "0" "has-text stall recovers via bare Enter and succeeds"
assert_eq "$(grep -c '^agent prompt t2 do the fix' "$HERDR_MOCK_LOG")" "1" \
  "has-text stall never resends the prompt text (would double-submit)"
assert_contains "$(cat "$HERDR_MOCK_LOG")" "agent send-keys t2 enter" \
  "has-text stall sends a bare Enter"

# --- indeterminate box state falls back to the safe bare-Enter path -----
reset_mock
HERDR_MOCK_STALL_CALLS=1 HERDR_MOCK_BOX=missing _chief_herdr_prompt t3 "do the fix"
assert_eq "$?" "0" "indeterminate box state still recovers"
assert_eq "$(grep -c '^agent prompt t3 do the fix' "$HERDR_MOCK_LOG")" "1" \
  "indeterminate box state does not risk a resend"
assert_contains "$(cat "$HERDR_MOCK_LOG")" "agent send-keys t3 enter" \
  "indeterminate box state falls back to bare Enter"

# --- a repeat stall fails loudly instead of looping forever -------------
reset_mock
HERDR_MOCK_STALL_CALLS=100 HERDR_MOCK_BOX=empty _chief_herdr_prompt t4 "do the fix" 2>"$WORK/t4.err"
assert_eq "$?" "1" "a stall that never recovers reports failure"
assert_eq "$(grep -c '^agent prompt t4 do the fix' "$HERDR_MOCK_LOG")" "3" \
  "recovery is bounded to two extra attempts, not unbounded retries"
assert_contains "$(cat "$WORK/t4.err")" "stalled and recovery did not start a turn" \
  "the failure message explains recovery didn't start a turn"

# --- an ordinary (non-stall) failure is reported, not treated as a stall
reset_mock
cat > "$WORK/bin/herdr" <<'FAKE_HERDR_FAIL'
#!/usr/bin/env bash
echo "$*" >> "$HERDR_MOCK_LOG"
case "$1 $2" in
  "agent prompt") echo "some other error" >&2; exit 1 ;;
  *) exit 1 ;;
esac
FAKE_HERDR_FAIL
chmod +x "$WORK/bin/herdr"
_chief_herdr_prompt t5 "do the fix" 2>"$WORK/t5.err"
assert_eq "$?" "1" "a non-stall prompt failure is not recovered from"
assert_contains "$(cat "$WORK/t5.err")" "some other error" \
  "the non-stall failure message passes through herdr's own error"
assert_not_contains "$(cat "$HERDR_MOCK_LOG")" "agent explain" \
  "a non-stall failure never inspects the prompt box"

harness_summary
