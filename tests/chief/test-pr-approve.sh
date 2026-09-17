#!/usr/bin/env bash
# test-pr-approve.sh - chief-pr-approve.sh against the mock provider.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-pr-approve:"

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

OUT=$("$CHIEF_BIN/chief-pr-approve.sh" t1)
assert_eq "$OUT" "approved: t1 -> https://example.invalid/mock/pr/7" "reports the approved PR"
assert_contains "$(cat "$CHIEF_PR_MOCK_LOG")" "pr_approve https://example.invalid/mock/pr/7" "calls pr_approve with the task's PR URL"

chief_meta_set t2 project /irrelevant
"$CHIEF_BIN/chief-pr-approve.sh" t2 >/dev/null 2>"$WORK/err"
assert_eq "$?" "1" "refuses a task with no recorded PR"

harness_summary
