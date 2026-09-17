#!/usr/bin/env bash
# test-pr-provider-gitlab.sh - chief-pr-provider-gitlab.sh's command
# construction, against a FAKE `glab` CLI stub. No network, no real MR.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-pr-provider-gitlab:"

if ! command -v jq >/dev/null 2>&1; then
  echo "  (skipped - jq not on PATH, required by chief-pr-provider-gitlab.sh)"
  exit 0
fi

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK/bin"

cat > "$WORK/bin/glab" <<'FAKE_GLAB'
#!/usr/bin/env bash
echo "$*" >> "$GLAB_MOCK_LOG"
case "$1 $2" in
  "mr create")
    echo "Creating merge request for chief/t1 into main"
    echo "https://gitlab.com/acme/widgets/-/merge_requests/9"
    ;;
  "mr view")
    case "${GLAB_MOCK_VIEW:-open}" in
      open) echo '{"state":"opened","draft":false,"detailed_merge_status":"mergeable"}' ;;
      draft) echo '{"state":"opened","draft":true,"detailed_merge_status":"mergeable"}' ;;
      blocked) echo '{"state":"opened","draft":false,"detailed_merge_status":"ci_still_running"}' ;;
    esac
    ;;
  "mr note") echo "note posted" ;;
  "mr approve") echo "approved" ;;
  "mr merge") echo "merged" ;;
  *)
    echo "fake-glab: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
FAKE_GLAB
chmod +x "$WORK/bin/glab"
export PATH="$WORK/bin:$PATH"
export GLAB_MOCK_LOG="$WORK/glab.log"
: > "$GLAB_MOCK_LOG"

. "$CHIEF_BIN/lib/chief-pr-provider-gitlab.sh"

: > "$GLAB_MOCK_LOG"
URL=$(pr_open "chief/t1" "main" "My title" "My body")
assert_eq "$URL" "https://gitlab.com/acme/widgets/-/merge_requests/9" "pr_open extracts the MR URL from glab's output"
assert_contains "$(cat "$GLAB_MOCK_LOG")" "mr create --source-branch chief/t1 --target-branch main --title My title --description My body --yes" \
  "pr_open calls glab mr create with source/target/title/description"

: > "$GLAB_MOCK_LOG"
export GLAB_MOCK_VIEW=open
OUT=$(pr_state "https://gitlab.com/acme/widgets/-/merge_requests/9")
assert_eq "$OUT" "" "pr_state prints nothing when the MR is clean"

: > "$GLAB_MOCK_LOG"
export GLAB_MOCK_VIEW=blocked
OUT=$(pr_state "https://gitlab.com/acme/widgets/-/merge_requests/9")
assert_contains "$OUT" "mergeable: ci_still_running" "pr_state reports a non-mergeable status"
unset GLAB_MOCK_VIEW

: > "$GLAB_MOCK_LOG"
pr_review "https://gitlab.com/acme/widgets/-/merge_requests/9" comment "looks fine" >/dev/null
assert_contains "$(cat "$GLAB_MOCK_LOG")" "mr note https://gitlab.com/acme/widgets/-/merge_requests/9 --message looks fine" \
  "pr_review posts a note for a comment verdict"

: > "$GLAB_MOCK_LOG"
pr_review "https://gitlab.com/acme/widgets/-/merge_requests/9" request-changes "fix this" >/dev/null
assert_contains "$(cat "$GLAB_MOCK_LOG")" "mr note https://gitlab.com/acme/widgets/-/merge_requests/9 --message fix this" \
  "pr_review also posts a note for request-changes (GitLab has no distinct review-decision primitive)"

: > "$GLAB_MOCK_LOG"
pr_approve "https://gitlab.com/acme/widgets/-/merge_requests/9" >/dev/null
assert_contains "$(cat "$GLAB_MOCK_LOG")" "mr approve https://gitlab.com/acme/widgets/-/merge_requests/9" "pr_approve approves"

: > "$GLAB_MOCK_LOG"
export GLAB_MOCK_VIEW=open
pr_merge "https://gitlab.com/acme/widgets/-/merge_requests/9" >/dev/null
assert_eq "$?" "0" "pr_merge succeeds when opened/non-draft/mergeable"
assert_contains "$(cat "$GLAB_MOCK_LOG")" "mr merge https://gitlab.com/acme/widgets/-/merge_requests/9 --yes" \
  "pr_merge defaults to a plain merge"
unset GLAB_MOCK_VIEW

: > "$GLAB_MOCK_LOG"
export GLAB_MOCK_VIEW=draft
pr_merge "https://gitlab.com/acme/widgets/-/merge_requests/9" >/dev/null 2>"$WORK/err"
assert_eq "$?" "1" "pr_merge refuses a draft MR"
assert_contains "$(cat "$WORK/err")" "still a draft" "pr_merge names the draft refusal"
unset GLAB_MOCK_VIEW

harness_summary
