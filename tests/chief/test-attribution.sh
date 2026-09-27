#!/usr/bin/env bash
# test-attribution.sh - chief_detect_ai_attribution (bin/lib/chief-attribution.sh).
# Detection only - never rewrites anything (see plugins/chief/skills/reviewer/SKILL.md).
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"
. "$CHIEF_BIN/lib/chief-attribution.sh"

echo "test-attribution:"

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

git init -q -b main "$WORK/repo"
( cd "$WORK/repo" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )

# --- a branch with no AI-attribution lines: clean, nothing printed --------
git -C "$WORK/repo" branch clean-branch main
( cd "$WORK/repo" && git checkout -q clean-branch \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "a normal commit" \
    && git checkout -q main )
BEFORE=$(git -C "$WORK/repo" rev-parse clean-branch)

OUT=$(chief_detect_ai_attribution "$WORK/repo" main clean-branch)
RC=$?
assert_eq "$RC" "0" "returns 0 when no AI-attribution line is present"
assert_eq "$OUT" "" "prints nothing when clean"
assert_eq "$(git -C "$WORK/repo" rev-parse clean-branch)" "$BEFORE" "never touches the branch's SHA - detection only"

# --- a branch with a Co-Authored-By trailer naming an AI ------------------
git -C "$WORK/repo" branch dirty-branch main
( cd "$WORK/repo" && git checkout -q dirty-branch \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$(printf 'fix: the thing\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>')" \
    && git checkout -q main )
BEFORE_DIRTY=$(git -C "$WORK/repo" rev-parse dirty-branch)

OUT=$(chief_detect_ai_attribution "$WORK/repo" main dirty-branch)
RC=$?
assert_eq "$RC" "1" "returns 1 when an AI-attribution trailer is present"
assert_contains "$OUT" "Co-Authored-By: Claude Sonnet 5" "prints the offending line"
assert_eq "$(git -C "$WORK/repo" rev-parse dirty-branch)" "$BEFORE_DIRTY" "never rewrites the commit - detection only"
assert_contains "$(git -C "$WORK/repo" log --format=%B -1 dirty-branch)" "Co-Authored-By: Claude Sonnet 5" \
  "the trailer is still in the actual commit message afterwards"

# --- a human co-author trailer is not a hit --------------------------------
git -C "$WORK/repo" branch human-branch main
( cd "$WORK/repo" && git checkout -q human-branch \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$(printf 'feat: thing\n\nCo-Authored-By: Jane Doe <jane@example.com>')" \
    && git checkout -q main )

chief_detect_ai_attribution "$WORK/repo" main human-branch >/dev/null
assert_eq "$?" "0" "a human co-author trailer is not flagged"

# --- a conventional-commit subject mentioning a tool name isn't a hit ------
git -C "$WORK/repo" branch subject-branch main
( cd "$WORK/repo" && git checkout -q subject-branch \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "docs: document the codex integration" \
    && git checkout -q main )

chief_detect_ai_attribution "$WORK/repo" main subject-branch >/dev/null
assert_eq "$?" "0" "a conventional-commit subject mentioning a tool name isn't a trailer, so it's not flagged"

# --- a freeform "Generated with Claude Code" marker line is a hit ----------
git -C "$WORK/repo" branch marker-branch main
( cd "$WORK/repo" && git checkout -q marker-branch \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$(printf 'chore: thing\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)')" \
    && git checkout -q main )

OUT=$(chief_detect_ai_attribution "$WORK/repo" main marker-branch)
assert_eq "$?" "1" "flags a freeform 'Generated with Claude Code' marker line"
assert_contains "$OUT" "Generated with" "prints the offending marker line"

# --- several offending commits: each is reported ---------------------------
git -C "$WORK/repo" branch multi-branch main
( cd "$WORK/repo" && git checkout -q multi-branch \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$(printf 'feat: a\n\nCo-Authored-By: Claude <noreply@anthropic.com>')" \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$(printf 'feat: b\n\nCo-Authored-By: GitHub Copilot <copilot@github.com>')" \
    && git checkout -q main )

OUT=$(chief_detect_ai_attribution "$WORK/repo" main multi-branch)
assert_eq "$?" "1" "flags a branch with multiple offending commits"
assert_eq "$(printf '%s\n' "$OUT" | grep -c 'Co-Authored-By')" "2" "reports one line per offending commit"

harness_summary
