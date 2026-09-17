#!/usr/bin/env bash
# test-pr-provider.sh - chief-pr-provider.sh's detection and loading logic.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-pr-provider:"

export CHIEF_ROOT="$REPO_ROOT/plugins/chief"
. "$CHIEF_BIN/lib/chief-pr-provider.sh"

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/gh-repo" "$WORK/gl-repo" "$WORK/ado-repo" "$WORK/unknown-repo"
git -C "$WORK/gh-repo" init -q
git -C "$WORK/gh-repo" remote add origin git@github.com:acme/widgets.git
git -C "$WORK/gl-repo" init -q
git -C "$WORK/gl-repo" remote add origin https://gitlab.com/acme/widgets.git
git -C "$WORK/ado-repo" init -q
git -C "$WORK/ado-repo" remote add origin https://dev.azure.com/acme/widgets/_git/widgets
git -C "$WORK/unknown-repo" init -q
git -C "$WORK/unknown-repo" remote add origin https://example.invalid/acme/widgets.git

assert_eq "$(chief_pr_detect_provider "$WORK/gh-repo")" "github" "detects github.com remotes"
assert_eq "$(chief_pr_detect_provider "$WORK/gl-repo")" "gitlab" "detects gitlab.com remotes"
assert_eq "$(chief_pr_detect_provider "$WORK/ado-repo")" "azuredevops" "detects dev.azure.com remotes"

chief_pr_detect_provider "$WORK/unknown-repo" >/dev/null 2>"$WORK/err"
assert_eq "$?" "1" "refuses to guess an unrecognized remote"
assert_contains "$(cat "$WORK/err")" "could not detect a provider" "names the failure reason"

export CHIEF_PR_PROVIDER=gitlab
assert_eq "$(chief_pr_detect_provider "$WORK/unknown-repo")" "gitlab" "CHIEF_PR_PROVIDER overrides detection"
unset CHIEF_PR_PROVIDER

chief_pr_load_provider mock
assert_eq "$(type -t pr_open)" "function" "chief_pr_load_provider sources the mock adapter's pr_open"

chief_pr_load_provider nope >/dev/null 2>"$WORK/err2"
assert_eq "$?" "1" "chief_pr_load_provider refuses an unknown provider name"
assert_contains "$(cat "$WORK/err2")" "unsupported provider" "names the bad provider"

harness_summary
