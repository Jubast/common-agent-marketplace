#!/usr/bin/env bash
# test-local-merge.sh - chief-local-merge.sh's fast-forward-only path, and
# its --pr removal message.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-local-merge:"

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

git init -q -b main "$WORK/project"
( cd "$WORK/project" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
git -C "$WORK/project" worktree add -q -b chief/t1 "$WORK/worktrees/t1"
( cd "$WORK/worktrees/t1" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m work )

export CHIEF_HOME="$WORK/.chief"
. "$CHIEF_BIN/lib/chief-paths.sh"
. "$CHIEF_BIN/lib/chief-meta.sh"

chief_meta_set t1 project "$WORK/project"
chief_meta_set t1 branch chief/t1
chief_meta_set t1 status working

"$CHIEF_BIN/chief-local-merge.sh" t1 >/dev/null 2>"$WORK/err-noconfirm"
assert_eq "$?" "1" "refuses to merge without --confirm"
assert_contains "$(cat "$WORK/err-noconfirm")" "--confirm" "names the missing-confirm refusal"
HEAD_MAIN_BEFORE=$(git -C "$WORK/project" rev-parse main)
assert_eq "$HEAD_MAIN_BEFORE" "$(git -C "$WORK/project" rev-parse HEAD)" "without --confirm, main is untouched"

OUT=$("$CHIEF_BIN/chief-local-merge.sh" t1 --confirm)
assert_contains "$OUT" "merged: t1 -> main in $WORK/project (fast-forward)" "fast-forwards the default branch once confirmed"

HEAD_MAIN=$(git -C "$WORK/project" rev-parse main)
HEAD_BRANCH=$(git -C "$WORK/worktrees/t1" rev-parse chief/t1)
assert_eq "$HEAD_MAIN" "$HEAD_BRANCH" "main now points at the task branch's commit"
assert_eq "$(chief_meta_get t1 status)" "merged" "advances the task's meta status away from working once merged"

"$CHIEF_BIN/chief-local-merge.sh" t1 --pr "https://example.invalid/pr/1" >/dev/null 2>"$WORK/err"
assert_eq "$?" "1" "refuses the removed --pr flag"
assert_contains "$(cat "$WORK/err")" "chief-pr-merge.sh" "points the caller at chief-pr-merge.sh instead"

harness_summary
