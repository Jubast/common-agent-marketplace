#!/usr/bin/env bash
# test-git-sync.sh - bin/lib/git-sync.sh's chief_sync_default_branch: a
# best-effort fetch+ff-only-merge of a project's default branch against
# origin, that only ever acts when the checkout is on that branch with a
# clean tree, and never fails its caller regardless.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"
. "$CHIEF_BIN/lib/git-sync.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "test-git-sync:"

# --- no origin remote at all: fetch fails, helper still returns 0 --------
mkdir -p "$WORK/no-origin" && cd "$WORK/no-origin" && git init -q -b main
git commit --allow-empty -q -m init

assert_success "sync: never fails the caller when there is no origin remote" -- \
  chief_sync_default_branch "$WORK/no-origin"

# --- a normal project with an origin remote -------------------------------
BARE="$WORK/origin.git"
git init -q --bare -b main "$BARE"

mkdir -p "$WORK/project" && cd "$WORK/project" && git init -q -b main
git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
git remote add origin "$BARE"
git push -q origin main

# A second clone advances origin/main independently, simulating another
# merge having landed there since this checkout last fetched.
git clone -q "$BARE" "$WORK/other"
(cd "$WORK/other" && git -c user.email=t@t -c user.name=t commit --allow-empty -q -m "advance origin" && git push -q origin main)

assert_success "sync: fast-forwards the local default branch when on it with a clean tree" -- \
  chief_sync_default_branch "$WORK/project"
assert_eq "$(git -C "$WORK/project" rev-parse main)" "$(git -C "$BARE" rev-parse main)" \
  "sync: local main now matches the freshly-fetched origin/main"

# --- not on the default branch: skipped -----------------------------------
(cd "$WORK/other" && git -c user.email=t@t -c user.name=t commit --allow-empty -q -m "advance origin again" && git push -q origin main)
git -C "$WORK/project" checkout -q -b feature
BEFORE=$(git -C "$WORK/project" rev-parse main)
assert_success "sync: never fails when the checkout is on another branch" -- \
  chief_sync_default_branch "$WORK/project"
assert_eq "$(git -C "$WORK/project" rev-parse main)" "$BEFORE" \
  "sync: local main is untouched while a different branch is checked out"

# --- on the default branch but with a dirty working tree: skipped --------
git -C "$WORK/project" checkout -q main
echo dirty > "$WORK/project/dirty.txt"
BEFORE=$(git -C "$WORK/project" rev-parse main)
assert_success "sync: never fails with an unclean working tree" -- \
  chief_sync_default_branch "$WORK/project"
assert_eq "$(git -C "$WORK/project" rev-parse main)" "$BEFORE" \
  "sync: local main is untouched with a dirty working tree"
rm -f "$WORK/project/dirty.txt"

# --- a local commit that diverges from origin: ff-only merge can't apply,
# --- helper still doesn't fail --------------------------------------------
git -C "$WORK/project" reset -q --hard "$BEFORE"
git -C "$WORK/project" -c user.email=t@t -c user.name=t commit --allow-empty -q -m "local-only work"
(cd "$WORK/other" && git -c user.email=t@t -c user.name=t commit --allow-empty -q -m "diverging origin work" && git push -q origin main)
BEFORE=$(git -C "$WORK/project" rev-parse main)
assert_success "sync: never fails when the ff-only merge itself can't apply (diverged history)" -- \
  chief_sync_default_branch "$WORK/project"
assert_eq "$(git -C "$WORK/project" rev-parse main)" "$BEFORE" \
  "sync: local main is untouched when it has diverged from origin"

harness_summary
