#!/usr/bin/env bash
# test-pr-state.sh - chief-pr-state.sh against the mock provider.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-pr-state:"

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

export CHIEF_HOME="$WORK/.chief"
. "$CHIEF_BIN/lib/chief-paths.sh"
. "$CHIEF_BIN/lib/chief-meta.sh"

chief_meta_set t1 project /irrelevant
chief_meta_set t1 pr_url "https://example.invalid/mock/pr/7"
chief_meta_set t1 pr_provider mock

export CHIEF_PR_MOCK_LOG="$WORK/mock.log"
: > "$CHIEF_PR_MOCK_LOG"

export CHIEF_PR_MOCK_STATE=""
OUT=$("$CHIEF_BIN/chief-pr-state.sh" t1)
assert_eq "$OUT" "" "prints nothing when the provider reports no blockers"
assert_contains "$(cat "$CHIEF_PR_MOCK_LOG")" "pr_state https://example.invalid/mock/pr/7" "calls pr_state with the task's PR URL"

export CHIEF_PR_MOCK_STATE="check: build failing"
OUT=$("$CHIEF_BIN/chief-pr-state.sh" t1)
assert_eq "$OUT" "check: build failing" "prints the provider's blocker line verbatim"

chief_meta_set t2 project /irrelevant
"$CHIEF_BIN/chief-pr-state.sh" t2 >/dev/null 2>"$WORK/err"
assert_eq "$?" "1" "refuses a task with no recorded PR"
assert_contains "$(cat "$WORK/err")" "missing required key" "names the missing pr_url"

harness_summary
