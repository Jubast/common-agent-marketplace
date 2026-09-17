#!/usr/bin/env bash
# test-pr-review.sh - chief-pr-review.sh against the mock provider.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-pr-review:"

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

OUT=$("$CHIEF_BIN/chief-pr-review.sh" t1 --comment "looks fine")
assert_eq "$OUT" "reviewed: t1 (comment)" "reports the comment verdict"
assert_contains "$(cat "$CHIEF_PR_MOCK_LOG")" "pr_review https://example.invalid/mock/pr/7 comment looks fine" \
  "posts a comment review with the given body"

: > "$CHIEF_PR_MOCK_LOG"
OUT=$("$CHIEF_BIN/chief-pr-review.sh" t1 --request-changes "fix this")
assert_eq "$OUT" "reviewed: t1 (request-changes)" "reports the request-changes verdict"
assert_contains "$(cat "$CHIEF_PR_MOCK_LOG")" "pr_review https://example.invalid/mock/pr/7 request-changes fix this" \
  "posts a request-changes review with the given body"

"$CHIEF_BIN/chief-pr-review.sh" t1 --comment "" >/dev/null 2>"$WORK/err-empty"
assert_eq "$?" "1" "refuses an empty review body"
assert_contains "$(cat "$WORK/err-empty")" "must not be empty" "names the empty-body refusal"

"$CHIEF_BIN/chief-pr-review.sh" t1 --bogus "x" >/dev/null 2>"$WORK/err-flag"
assert_eq "$?" "1" "refuses an unknown flag"

harness_summary
