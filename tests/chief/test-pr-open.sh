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
. "$CHIEF_BIN/lib/chief-paths.sh"
. "$CHIEF_BIN/lib/chief-meta.sh"

mkdir -p "$DATA/t1"
cat > "$DATA/t1/brief.md" <<'EOF'
# Task

## Operator's intent
Do the thing.

## Chief's spec
(none)
EOF

chief_meta_set t1 project "$WORK/project"
chief_meta_set t1 branch chief/t1
chief_meta_set t1 worktree "$WORK/worktrees/t1"

export CHIEF_PR_PROVIDER=mock
export CHIEF_PR_MOCK_LOG="$WORK/mock.log"
export CHIEF_PR_MOCK_URL="https://example.invalid/mock/pr/7"
: > "$CHIEF_PR_MOCK_LOG"

OUT=$("$CHIEF_BIN/chief-pr-open.sh" t1)
RC=$?
assert_eq "$RC" "0" "chief-pr-open.sh succeeds"
assert_eq "$OUT" "opened: t1 -> https://example.invalid/mock/pr/7 (mock)" "prints the opened PR's URL and provider"

assert_contains "$(cat "$CHIEF_PR_MOCK_LOG")" "pr_open chief/t1 main Do the thing. Do the thing." \
  "pr_open is called with the branch, base, and the intent as both title and body"

assert_eq "$(chief_meta_get t1 pr_url)" "https://example.invalid/mock/pr/7" "records pr_url in task meta"
assert_eq "$(chief_meta_get t1 pr_provider)" "mock" "records pr_provider in task meta"

REMOTE_HEAD=$(git -C "$WORK/remote.git" rev-parse chief/t1 2>/dev/null || echo MISSING)
LOCAL_HEAD=$(git -C "$WORK/worktrees/t1" rev-parse chief/t1)
assert_eq "$REMOTE_HEAD" "$LOCAL_HEAD" "the branch was actually pushed to origin"

"$CHIEF_BIN/chief-pr-open.sh" t1 >/dev/null 2>"$WORK/err-dup"
assert_eq "$?" "1" "refuses to open a second PR for the same task"
assert_contains "$(cat "$WORK/err-dup")" "PR already open" "names the existing PR in the refusal"

git -C "$WORK/project" worktree add -q -b chief/t2 "$WORK/worktrees/t2"
mkdir -p "$DATA/t2"
printf '## Operator'"'"'s intent\nOther thing.\n' > "$DATA/t2/brief.md"
chief_meta_set t2 project "$WORK/project"
chief_meta_set t2 branch chief/t2
chief_meta_set t2 worktree "$WORK/worktrees/t2"
echo dirty > "$WORK/worktrees/t2/scratch.txt"

"$CHIEF_BIN/chief-pr-open.sh" t2 >/dev/null 2>"$WORK/err-dirty"
assert_eq "$?" "1" "refuses a dirty worktree"
assert_contains "$(cat "$WORK/err-dirty")" "uncommitted changes" "names the dirty-worktree refusal"

harness_summary
