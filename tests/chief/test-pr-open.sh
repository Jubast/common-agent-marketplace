#!/usr/bin/env bash
# test-pr-open.sh - chief-pr-open.sh against the mock provider. No network.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-pr-open:"

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# --- a real, local, pushable "origin" -----------------------------------
git init -q -b main --bare "$WORK/remote.git"
git clone -q "$WORK/remote.git" "$WORK/project"
( cd "$WORK/project" \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
    && git push -q origin main )

git -C "$WORK/project" worktree add -q -b chief/t1 "$WORK/worktrees/t1"
( cd "$WORK/worktrees/t1" \
    && printf 'hi\n' > file.txt \
    && git add file.txt \
    && git -c user.email=t@t -c user.name=t commit -q -m work )

export CHIEF_HOME="$WORK/.chief"
. "$CHIEF_BIN/lib/paths.sh"
. "$CHIEF_BIN/lib/meta.sh"

chief_meta_set t1 project "$WORK/project"
chief_meta_set t1 branch chief/t1
chief_meta_set t1 worktree "$WORK/worktrees/t1"
chief_meta_set t1 mode ship
chief_meta_set t1 status working

export CHIEF_PR_PROVIDER=mock
export CHIEF_PR_MOCK_LOG="$WORK/mock.log"
export CHIEF_PR_MOCK_URL="https://example.invalid/mock/pr/7"
: > "$CHIEF_PR_MOCK_LOG"

"$CHIEF_BIN/pr/chief-pr-open.sh" t1 --title "My title" --body "My body" >/dev/null 2>"$WORK/err-noconfirm"
assert_eq "$?" "1" "refuses to open a PR without --confirm"
assert_contains "$(cat "$WORK/err-noconfirm")" "--confirm" "names the missing-confirm refusal"
assert_eq "$(cat "$CHIEF_PR_MOCK_LOG")" "" "never calls the provider without --confirm"
assert_eq "$(git -C "$WORK/remote.git" rev-parse --verify chief/t1 2>/dev/null || echo MISSING)" "MISSING" \
  "never pushes the branch without --confirm"

"$CHIEF_BIN/pr/chief-pr-open.sh" t1 --confirm --body "My body" >/dev/null 2>"$WORK/err-notitle"
assert_eq "$?" "1" "refuses to open a PR without --title"
assert_contains "$(cat "$WORK/err-notitle")" "--title is required" "names the missing-title refusal"
assert_eq "$(cat "$CHIEF_PR_MOCK_LOG")" "" "never calls the provider without --title"

"$CHIEF_BIN/pr/chief-pr-open.sh" t1 --confirm --title "My title" >/dev/null 2>"$WORK/err-nobody"
assert_eq "$?" "1" "refuses to open a PR without --body"
assert_contains "$(cat "$WORK/err-nobody")" "--body is required" "names the missing-body refusal"
assert_eq "$(cat "$CHIEF_PR_MOCK_LOG")" "" "never calls the provider without --body"

OUT=$("$CHIEF_BIN/pr/chief-pr-open.sh" t1 --confirm --title "My title" --body "My body")
RC=$?
assert_eq "$RC" "0" "chief-pr-open.sh succeeds once confirmed with title and body"
assert_eq "$OUT" "opened: t1 -> https://example.invalid/mock/pr/7 (mock)" "prints the opened PR's URL and provider"

assert_contains "$(cat "$CHIEF_PR_MOCK_LOG")" "pr_open chief/t1 main My title My body" \
  "pr_open is called with the caller's own title and body, verbatim"

assert_eq "$(chief_meta_get t1 pr_url)" "https://example.invalid/mock/pr/7" "records pr_url in task meta"
assert_eq "$(chief_meta_get t1 pr_provider)" "mock" "records pr_provider in task meta"
assert_eq "$(chief_meta_get t1 status)" "pr-opened" "advances the task's meta status away from working once the PR is opened"

REMOTE_HEAD=$(git -C "$WORK/remote.git" rev-parse chief/t1 2>/dev/null || echo MISSING)
LOCAL_HEAD=$(git -C "$WORK/worktrees/t1" rev-parse chief/t1)
assert_eq "$REMOTE_HEAD" "$LOCAL_HEAD" "the branch was actually pushed to origin"

"$CHIEF_BIN/pr/chief-pr-open.sh" t1 --confirm --title "My title" --body "My body" >/dev/null 2>"$WORK/err-dup"
assert_eq "$?" "1" "refuses to open a second PR for the same task"
assert_contains "$(cat "$WORK/err-dup")" "PR already open" "names the existing PR in the refusal"

git -C "$WORK/project" worktree add -q -b chief/t2 "$WORK/worktrees/t2"
chief_meta_set t2 project "$WORK/project"
chief_meta_set t2 branch chief/t2
chief_meta_set t2 worktree "$WORK/worktrees/t2"
chief_meta_set t2 mode ship
echo dirty > "$WORK/worktrees/t2/scratch.txt"

"$CHIEF_BIN/pr/chief-pr-open.sh" t2 --confirm --title "T2 title" --body "T2 body" >/dev/null 2>"$WORK/err-dirty"
assert_eq "$?" "1" "refuses a dirty worktree"
assert_contains "$(cat "$WORK/err-dirty")" "uncommitted changes" "names the dirty-worktree refusal"

# --- a provider that returns a malformed (multi-line) URL ---------------
git -C "$WORK/project" worktree add -q -b chief/t4 "$WORK/worktrees/t4"
( cd "$WORK/worktrees/t4" \
    && printf 'hi\n' > file.txt \
    && git add file.txt \
    && git -c user.email=t@t -c user.name=t commit -q -m work )

chief_meta_set t4 project "$WORK/project"
chief_meta_set t4 branch chief/t4
chief_meta_set t4 worktree "$WORK/worktrees/t4"
chief_meta_set t4 mode ship

export CHIEF_PR_MOCK_URL=$'https://example.invalid/mock/pr/9\nsome stray extra line'
: > "$CHIEF_PR_MOCK_LOG"

"$CHIEF_BIN/pr/chief-pr-open.sh" t4 --confirm --title "T4 title" --body "T4 body" >/dev/null 2>"$WORK/err-multiline"
assert_eq "$?" "1" "refuses a multi-line URL from the provider"
assert_contains "$(cat "$WORK/err-multiline")" "more than one line" "names the malformed-URL refusal"
assert_eq "$(chief_meta_get t4 pr_url 2>/dev/null || true)" "" "does not record the malformed URL in task meta"

# --- a scout task (a report, not a branch meant to be pushed) -----------
git -C "$WORK/project" worktree add -q -b chief/t5 "$WORK/worktrees/t5"
chief_meta_set t5 project "$WORK/project"
chief_meta_set t5 branch chief/t5
chief_meta_set t5 worktree "$WORK/worktrees/t5"
chief_meta_set t5 mode scout

export CHIEF_PR_MOCK_URL="https://example.invalid/mock/pr/10"
: > "$CHIEF_PR_MOCK_LOG"
"$CHIEF_BIN/pr/chief-pr-open.sh" t5 --confirm --title "T5 title" --body "T5 body" >/dev/null 2>"$WORK/err-scout"
assert_eq "$?" "1" "refuses a scout task - its deliverable is a report, not a branch"
assert_contains "$(cat "$WORK/err-scout")" "not a ship task" "names the mode refusal"
assert_eq "$(chief_meta_get t5 pr_url 2>/dev/null || true)" "" "does not record a pr_url for the refused scout"
assert_eq "$(cat "$CHIEF_PR_MOCK_LOG")" "" "refuses before ever calling the provider - no push, no PR"
assert_eq "$(git -C "$WORK/remote.git" rev-parse --verify chief/t5 2>/dev/null || echo MISSING)" "MISSING" \
  "refuses before ever pushing the scout's branch to origin"

harness_summary
