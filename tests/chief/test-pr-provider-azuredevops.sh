#!/usr/bin/env bash
# test-pr-provider-azuredevops.sh - chief-pr-provider-azuredevops.sh's
# command construction, against a FAKE `az` CLI stub. No network, no real PR.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-pr-provider-azuredevops:"

if ! command -v jq >/dev/null 2>&1; then
  echo "  (skipped - jq not on PATH, required by chief-pr-provider-azuredevops.sh)"
  exit 0
fi

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK/bin"

cat > "$WORK/bin/az" <<'FAKE_AZ'
#!/usr/bin/env bash
echo "$*" >> "$AZ_MOCK_LOG"
case "$1 $2 $3" in
  "repos pr create")
    echo '{"pullRequestId": 55}'
    ;;
  "repos pr show")
    case "${AZ_MOCK_SHOW:-active}" in
      active) echo '{"status":"active","isDraft":false,"mergeStatus":"succeeded"}' ;;
      draft) echo '{"status":"active","isDraft":true,"mergeStatus":"succeeded"}' ;;
      conflicts) echo '{"status":"active","isDraft":false,"mergeStatus":"conflicts"}' ;;
    esac
    ;;
  "repos pr set-vote") echo "voted" ;;
  "repos pr thread") echo "thread created" ;;
  "repos pr policy")
    case "${AZ_MOCK_POLICY:-clean}" in
      clean) echo '[]' ;;
      running) echo '[{"status":"running","configuration":{"type":{"displayName":"build"}}}]' ;;
    esac
    ;;
  "repos pr update") echo "updated" ;;
  *)
    echo "fake-az: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
FAKE_AZ
chmod +x "$WORK/bin/az"
export PATH="$WORK/bin:$PATH"
export AZ_MOCK_LOG="$WORK/az.log"
: > "$AZ_MOCK_LOG"

. "$CHIEF_BIN/lib/chief-pr-provider-azuredevops.sh"

mkdir -p "$WORK/repo"
git -C "$WORK/repo" init -q
git -C "$WORK/repo" remote add origin https://dev.azure.com/acme/widgets/_git/widgets

: > "$AZ_MOCK_LOG"
URL=$(cd "$WORK/repo" && pr_open "chief/t1" "main" "My title" "My body")
assert_eq "$URL" "https://dev.azure.com/acme/widgets/_git/widgets/pullrequest/55" \
  "pr_open builds the web URL from the parsed remote plus the new pull request id"
assert_contains "$(cat "$AZ_MOCK_LOG")" "repos pr create --organization https://dev.azure.com/acme --project widgets --repository widgets --source-branch chief/t1 --target-branch main --title My title --description My body --output json" \
  "pr_open calls az repos pr create with org/project/repository/source/target/title/description"

PR_URL="https://dev.azure.com/acme/widgets/_git/widgets/pullrequest/55"

: > "$AZ_MOCK_LOG"
export AZ_MOCK_SHOW=active
OUT=$(pr_state "$PR_URL")
assert_eq "$OUT" "" "pr_state prints nothing when the PR is clean"

: > "$AZ_MOCK_LOG"
export AZ_MOCK_SHOW=conflicts
OUT=$(pr_state "$PR_URL")
assert_contains "$OUT" "mergeStatus: conflicts" "pr_state reports a non-succeeded mergeStatus"
unset AZ_MOCK_SHOW

: > "$AZ_MOCK_LOG"
pr_approve "$PR_URL" >/dev/null
assert_contains "$(cat "$AZ_MOCK_LOG")" "repos pr set-vote --organization https://dev.azure.com/acme --id 55 --vote approve" "pr_approve casts an approve vote"

: > "$AZ_MOCK_LOG"
export AZ_MOCK_SHOW=active
pr_merge "$PR_URL" >/dev/null
assert_eq "$?" "0" "pr_merge succeeds when active/non-draft/succeeded"
assert_contains "$(cat "$AZ_MOCK_LOG")" "repos pr update --organization https://dev.azure.com/acme --id 55" "pr_merge completes the PR via az repos pr update"
unset AZ_MOCK_SHOW

: > "$AZ_MOCK_LOG"
export AZ_MOCK_SHOW=draft
pr_merge "$PR_URL" >/dev/null 2>"$WORK/err"
assert_eq "$?" "1" "pr_merge refuses a draft PR"
assert_contains "$(cat "$WORK/err")" "still a draft" "pr_merge names the draft refusal"
unset AZ_MOCK_SHOW

: > "$AZ_MOCK_LOG"
export AZ_MOCK_SHOW=active
export AZ_MOCK_POLICY=running
pr_merge "$PR_URL" >/dev/null 2>"$WORK/err-policy"
assert_eq "$?" "1" "pr_merge refuses while a required policy is still running"
assert_contains "$(cat "$WORK/err-policy")" "blocking policies" "pr_merge names the blocking-policy refusal"
unset AZ_MOCK_SHOW AZ_MOCK_POLICY

harness_summary
