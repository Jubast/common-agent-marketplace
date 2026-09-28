#!/usr/bin/env bash
# test-pr-update.sh - chief-pr-update.sh against the mock provider. No network.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-pr-update:"

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
    && git -c user.email=t@t -c user.name=t commit -q -m work \
    && git push -q -u origin chief/t1 )

export CHIEF_HOME="$WORK/.chief"
. "$CHIEF_BIN/lib/paths.sh"
. "$CHIEF_BIN/lib/meta.sh"

chief_meta_set t1 project "$WORK/project"
chief_meta_set t1 branch chief/t1
chief_meta_set t1 worktree "$WORK/worktrees/t1"
chief_meta_set t1 mode ship
chief_meta_set t1 status pr-opened
chief_meta_set t1 pr_url "https://example.invalid/mock/pr/7"
chief_meta_set t1 pr_provider mock

export CHIEF_PR_PROVIDER=mock
export CHIEF_PR_MOCK_LOG="$WORK/mock.log"
: > "$CHIEF_PR_MOCK_LOG"

"$CHIEF_BIN/pr/chief-pr-update.sh" t1 --title "New title" --body "New body" >/dev/null 2>"$WORK/err-noconfirm"
assert_eq "$?" "1" "refuses to update a PR without --confirm"
assert_contains "$(cat "$WORK/err-noconfirm")" "--confirm" "names the missing-confirm refusal"
assert_eq "$(cat "$CHIEF_PR_MOCK_LOG")" "" "never calls the provider without --confirm"

# --- a task with no PR open yet ------------------------------------------
git -C "$WORK/project" worktree add -q -b chief/t2 "$WORK/worktrees/t2"
chief_meta_set t2 project "$WORK/project"
chief_meta_set t2 branch chief/t2
chief_meta_set t2 worktree "$WORK/worktrees/t2"
chief_meta_set t2 mode ship
chief_meta_set t2 status working

"$CHIEF_BIN/pr/chief-pr-update.sh" t2 --confirm --title "T2 title" >/dev/null 2>"$WORK/err-nopr"
assert_eq "$?" "1" "refuses to update a task with no PR open yet"
assert_contains "$(cat "$WORK/err-nopr")" "chief-pr-open.sh" "points the caller at chief-pr-open.sh instead"
assert_eq "$(cat "$CHIEF_PR_MOCK_LOG")" "" "never calls the provider when there is no PR to update"
assert_eq "$(git -C "$WORK/remote.git" rev-parse --verify chief/t2 2>/dev/null || echo MISSING)" "MISSING" \
  "never pushes the branch of a task with no PR open yet"

# --- pushing a new commit, updating title/body ---------------------------
( cd "$WORK/worktrees/t1" \
    && printf 'more\n' > more.txt \
    && git add more.txt \
    && git -c user.email=t@t -c user.name=t commit -q -m "follow-up work" )

OUT=$("$CHIEF_BIN/pr/chief-pr-update.sh" t1 --confirm --title "New title" --body "New body")
RC=$?
assert_eq "$RC" "0" "chief-pr-update.sh succeeds with a new commit and title/body"
assert_eq "$OUT" "updated: t1 -> https://example.invalid/mock/pr/7 (mock)" "prints the updated PR's URL and provider"

REMOTE_HEAD=$(git -C "$WORK/remote.git" rev-parse chief/t1 2>/dev/null || echo MISSING)
LOCAL_HEAD=$(git -C "$WORK/worktrees/t1" rev-parse chief/t1)
assert_eq "$REMOTE_HEAD" "$LOCAL_HEAD" "the new commit was actually pushed to origin"

assert_contains "$(cat "$CHIEF_PR_MOCK_LOG")" "pr_update https://example.invalid/mock/pr/7 New title New body" \
  "pr_update is called with the caller's title and body when given"

# --- push-only, no title/body given --------------------------------------
( cd "$WORK/worktrees/t1" \
    && printf 'again\n' > again.txt \
    && git add again.txt \
    && git -c user.email=t@t -c user.name=t commit -q -m "second follow-up" )

: > "$CHIEF_PR_MOCK_LOG"
OUT2=$("$CHIEF_BIN/pr/chief-pr-update.sh" t1 --confirm)
RC2=$?
assert_eq "$RC2" "0" "chief-pr-update.sh succeeds push-only, with no title/body"
assert_eq "$OUT2" "updated: t1 -> https://example.invalid/mock/pr/7 (mock)" "still prints the updated PR's URL and provider"

REMOTE_HEAD2=$(git -C "$WORK/remote.git" rev-parse chief/t1 2>/dev/null || echo MISSING)
LOCAL_HEAD2=$(git -C "$WORK/worktrees/t1" rev-parse chief/t1)
assert_eq "$REMOTE_HEAD2" "$LOCAL_HEAD2" "the second follow-up commit was pushed even with no title/body given"
assert_eq "$(cat "$CHIEF_PR_MOCK_LOG")" "" "never calls the provider's pr_update when title and body are both omitted"

# --- a dirty worktree -----------------------------------------------------
echo dirty > "$WORK/worktrees/t1/scratch.txt"
"$CHIEF_BIN/pr/chief-pr-update.sh" t1 --confirm --title "Dirty title" >/dev/null 2>"$WORK/err-dirty"
assert_eq "$?" "1" "refuses a dirty worktree"
assert_contains "$(cat "$WORK/err-dirty")" "uncommitted changes" "names the dirty-worktree refusal"
rm -f "$WORK/worktrees/t1/scratch.txt"

harness_summary
