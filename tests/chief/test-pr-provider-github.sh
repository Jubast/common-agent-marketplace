#!/usr/bin/env bash
# test-pr-provider-github.sh - chief-pr-provider-github.sh's command
# construction, against a FAKE `gh` CLI stub. No network, no real PR.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-pr-provider-github:"

if ! command -v jq >/dev/null 2>&1; then
  echo "  (skipped - jq not on PATH, required by chief-pr-provider-github.sh)"
  exit 0
fi

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK/bin"

cat > "$WORK/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
echo "$*" >> "$GH_MOCK_LOG"
case "$1" in
  api)
    echo '{"id":123}'
    ;;
  *)
    case "$1 $2" in
      "pr create")
        echo "https://github.com/acme/widgets/pull/42"
        ;;
      "pr view")
        case "${GH_MOCK_VIEW:-open}" in
          open) echo '{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"","headRefOid":"abc123","statusCheckRollup":[]}' ;;
          draft) echo '{"state":"OPEN","isDraft":true,"mergeable":"MERGEABLE","reviewDecision":"","headRefOid":"abc123","statusCheckRollup":[]}' ;;
          failing) echo '{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"","headRefOid":"abc123","statusCheckRollup":[{"name":"ci","conclusion":"FAILURE"}]}' ;;
          checks_failing) echo '{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"","headRefOid":"abc123","statusCheckRollup":[{"name":"ci","conclusion":"FAILURE"}]}' ;;
          changes_requested) echo '{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"CHANGES_REQUESTED","headRefOid":"abc123","statusCheckRollup":[]}' ;;
          merged) echo '{"state":"MERGED","isDraft":false,"mergeable":"UNKNOWN","reviewDecision":"","headRefOid":"abc123","statusCheckRollup":[]}' ;;
        esac
        ;;
      "pr review") echo '{"ok":true}' ;;
      "pr merge") echo "merged" ;;
      *)
        echo "fake-gh: unhandled invocation: $*" >&2
        exit 1
        ;;
    esac
    ;;
esac
FAKE_GH
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"
export GH_MOCK_LOG="$WORK/gh.log"
: > "$GH_MOCK_LOG"

. "$CHIEF_BIN/lib/chief-pr-provider-github.sh"

: > "$GH_MOCK_LOG"
URL=$(pr_open "chief/t1" "main" "My title" "My body")
assert_eq "$URL" "https://github.com/acme/widgets/pull/42" "pr_open returns the URL gh prints"
assert_contains "$(cat "$GH_MOCK_LOG")" "pr create --head chief/t1 --base main --title My title --body My body" \
  "pr_open calls gh pr create with head/base/title/body"

: > "$GH_MOCK_LOG"
export GH_MOCK_VIEW=open
OUT=$(pr_state "https://github.com/acme/widgets/pull/42")
assert_eq "$OUT" "" "pr_state prints nothing when the PR is clean"

: > "$GH_MOCK_LOG"
export GH_MOCK_VIEW=failing
OUT=$(pr_state "https://github.com/acme/widgets/pull/42")
assert_contains "$OUT" "check: ci FAILURE" "pr_state reports a failing check"
unset GH_MOCK_VIEW

: > "$GH_MOCK_LOG"
pr_review "https://github.com/acme/widgets/pull/42" comment "looks fine" >/dev/null
assert_contains "$(cat "$GH_MOCK_LOG")" "pr review https://github.com/acme/widgets/pull/42 --comment --body looks fine" \
  "pr_review posts a --comment review"

: > "$GH_MOCK_LOG"
pr_review "https://github.com/acme/widgets/pull/42" request-changes "fix this" >/dev/null
assert_contains "$(cat "$GH_MOCK_LOG")" "pr review https://github.com/acme/widgets/pull/42 --request-changes --body fix this" \
  "pr_review posts a --request-changes review"

: > "$GH_MOCK_LOG"
pr_approve "https://github.com/acme/widgets/pull/42" >/dev/null
assert_contains "$(cat "$GH_MOCK_LOG")" "pr review https://github.com/acme/widgets/pull/42 --approve" "pr_approve approves"

: > "$GH_MOCK_LOG"
export GH_MOCK_VIEW=open
pr_merge "https://github.com/acme/widgets/pull/42" >/dev/null
assert_eq "$?" "0" "pr_merge succeeds when open/non-draft/mergeable"
assert_contains "$(cat "$GH_MOCK_LOG")" "pr merge https://github.com/acme/widgets/pull/42 --squash --match-head-commit abc123" \
  "pr_merge defaults to --squash and matches the current head"
unset GH_MOCK_VIEW

: > "$GH_MOCK_LOG"
export GH_MOCK_VIEW=draft
pr_merge "https://github.com/acme/widgets/pull/42" >/dev/null 2>"$WORK/err"
assert_eq "$?" "1" "pr_merge refuses a draft PR"
assert_contains "$(cat "$WORK/err")" "still a draft" "pr_merge names the draft refusal"
unset GH_MOCK_VIEW

: > "$GH_MOCK_LOG"
export GH_MOCK_VIEW=checks_failing
pr_merge "https://github.com/acme/widgets/pull/42" >/dev/null 2>"$WORK/err"
assert_eq "$?" "1" "pr_merge refuses a PR with blocking checks"
assert_contains "$(cat "$WORK/err")" "blocking checks" "pr_merge names the blocking checks refusal"
# Guard the guard: the fake gh ignores its own --json field list and always
# emits statusCheckRollup, so the two asserts above would still pass even if
# pr_merge stopped asking gh for statusCheckRollup at all. Assert the actual
# logged `gh pr view` call for the merge path requested that field.
PR_VIEW_LINE=$(grep '^pr view' "$GH_MOCK_LOG")
assert_contains "$PR_VIEW_LINE" "statusCheckRollup" \
  "pr_merge's gh pr view call actually requests statusCheckRollup in --json"
unset GH_MOCK_VIEW

: > "$GH_MOCK_LOG"
export GH_MOCK_VIEW=changes_requested
pr_merge "https://github.com/acme/widgets/pull/42" >/dev/null 2>"$WORK/err"
assert_eq "$?" "1" "pr_merge refuses a PR with an outstanding changes-requested review, even with no failing checks and mergeable=true"
assert_contains "$(cat "$WORK/err")" "changes requested" "pr_merge names the changes-requested refusal"
assert_not_contains "$(cat "$GH_MOCK_LOG")" "pr merge" "pr_merge never calls gh pr merge when changes are requested"
PR_VIEW_LINE2=$(grep '^pr view' "$GH_MOCK_LOG")
assert_contains "$PR_VIEW_LINE2" "reviewDecision" \
  "pr_merge's gh pr view call actually requests reviewDecision in --json"
unset GH_MOCK_VIEW

: > "$GH_MOCK_LOG"
export GH_MOCK_VIEW=open
pr_review_line "https://github.com/acme/widgets/pull/42" "src/limiter.go" 42 "off by one" >/dev/null
assert_eq "$?" "0" "pr_review_line succeeds"
assert_contains "$(cat "$GH_MOCK_LOG")" "pr view https://github.com/acme/widgets/pull/42 --json headRefOid" \
  "pr_review_line reads the current head live before posting"
assert_contains "$(cat "$GH_MOCK_LOG")" "api repos/acme/widgets/pulls/42/comments -f body=off by one -f commit_id=abc123 -f path=src/limiter.go -F line=42 -f side=RIGHT" \
  "pr_review_line posts to the pulls/comments endpoint with body, the live head as commit_id, path, line, and side"
unset GH_MOCK_VIEW

: > "$GH_MOCK_LOG"
export GH_MOCK_VIEW=merged
pr_merged "https://github.com/acme/widgets/pull/42"
assert_eq "$?" "0" "pr_merged reports merged when gh reports state MERGED"
unset GH_MOCK_VIEW

: > "$GH_MOCK_LOG"
export GH_MOCK_VIEW=open
pr_merged "https://github.com/acme/widgets/pull/42"
assert_eq "$?" "1" "pr_merged reports not-merged for an open PR"
unset GH_MOCK_VIEW

harness_summary
