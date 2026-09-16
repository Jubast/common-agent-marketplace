#!/usr/bin/env bash
# test-send.sh - chief-send.sh: durable steering inbox + doorbell.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/project" && cd "$WORK/project" && git init -q -b master
git commit --allow-empty -q -m init
export CHIEF_HOME="$WORK/.chief"
export CHIEF_BACKEND=mock
SEND="$BIN/chief-send.sh"
SPAWN="$BIN/chief-spawn.sh"

echo "test-send:"

assert_failure "refuses an unknown task id" -- "$SEND" nope "hi"

timeout 10 "$SPAWN" t-1 "$WORK/project" --mode ship --intent "test" --spec "test" >/dev/null

assert_failure "refuses an empty message" -- "$SEND" t-1 "   "

assert_success "sends the first message" -- "$SEND" t-1 "please also add a README note"
assert_success "sends a second message" -- "$SEND" t-1 "and run the tests"
assert_file_exists "$CHIEF_HOME/state/t-1.inbox/001.msg" "first message numbered 001"
assert_file_exists "$CHIEF_HOME/state/t-1.inbox/002.msg" "second message numbered 002"
assert_eq "$(cat "$CHIEF_HOME/state/t-1.inbox/001.msg")" "please also add a README note" "message text is stored verbatim"

mv "$CHIEF_HOME/state/t-1.inbox/001.msg" "$CHIEF_HOME/state/t-1.inbox/handled/"
assert_success "sends a third message after the first was handled" -- "$SEND" t-1 "third message"
assert_file_exists "$CHIEF_HOME/state/t-1.inbox/003.msg" "numbering continues from handled/ history, never reuses 001"

assert_success "sends a special key" -- "$SEND" t-1 --key Enter
assert_contains "$(cat "$CHIEF_HOME/state/t-1.term.log")" "send: Enter" "the key reached the backend"
assert_contains "$(cat "$CHIEF_HOME/state/t-1.term.log")" "instruction waiting in" "an ordinary message rings a doorbell line, not the raw text"

harness_summary
