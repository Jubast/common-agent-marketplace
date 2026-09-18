#!/usr/bin/env bash
# test-pr-merge.sh - chief-pr-merge.sh against the mock provider.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-pr-merge:"

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

"$CHIEF_BIN/chief-pr-merge.sh" t1 >/dev/null 2>"$WORK/err-noconfirm"
assert_eq "$?" "1" "refuses to merge without --confirm"
assert_contains "$(cat "$WORK/err-noconfirm")" "--confirm" "names the missing-confirm refusal"
assert_eq "$(cat "$CHIEF_PR_MOCK_LOG")" "" "never calls the provider without --confirm"

OUT=$("$CHIEF_BIN/chief-pr-merge.sh" t1 --confirm)
assert_eq "$OUT" "merged: t1 via mock PR https://example.invalid/mock/pr/7" "reports the merged PR and provider"
assert_contains "$(cat "$CHIEF_PR_MOCK_LOG")" "pr_merge https://example.invalid/mock/pr/7 --squash" \
  "defaults to --squash (the recommended strategy) when no method is given, uniformly - not left to whatever each provider defaults to on its own"

: > "$CHIEF_PR_MOCK_LOG"
"$CHIEF_BIN/chief-pr-merge.sh" t1 --confirm --rebase >/dev/null
assert_contains "$(cat "$CHIEF_PR_MOCK_LOG")" "pr_merge https://example.invalid/mock/pr/7 --rebase" "passes an explicit method through"

: > "$CHIEF_PR_MOCK_LOG"
"$CHIEF_BIN/chief-pr-merge.sh" t1 --rebase --confirm >/dev/null
assert_contains "$(cat "$CHIEF_PR_MOCK_LOG")" "pr_merge https://example.invalid/mock/pr/7 --rebase" "accepts --confirm and the method in either order"

export CHIEF_PR_MOCK_MERGE_FAIL=1
"$CHIEF_BIN/chief-pr-merge.sh" t1 --confirm >/dev/null 2>"$WORK/err"
assert_eq "$?" "1" "refuses when the provider refuses the merge"
assert_contains "$(cat "$WORK/err")" "merge failed" "names the merge failure"
unset CHIEF_PR_MOCK_MERGE_FAIL

harness_summary
