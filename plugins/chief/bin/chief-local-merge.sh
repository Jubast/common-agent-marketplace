#!/usr/bin/env bash
# chief-local-merge.sh - local-only fast-forward merge. Requires --confirm -
# only pass it once the operator has explicitly said to merge <id>. Use
# chief-pr-merge.sh instead to merge an open PR/MR.
#
# Usage: chief-local-merge.sh <id> --confirm   -> local git merge --ff-only
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"

fail() { echo "chief-local-merge: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-local-merge.sh <id> --confirm"
chief_meta_exists "$ID" || fail "no such task: $ID"
shift

if [ "${1:-}" = "--pr" ]; then
  fail "--pr was removed - use chief-pr-merge.sh $ID instead"
fi

[ "${1:-}" = "--confirm" ] || fail "refusing to merge without --confirm - only pass it once the operator has explicitly said to merge $ID in this conversation"

PROJECT=$(chief_meta_require "$ID" project)
BRANCH=$(chief_meta_require "$ID" branch)

DEFAULT=$(git -C "$PROJECT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || true
[ -n "$DEFAULT" ] || DEFAULT=$(git -C "$PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null || echo main)

CUR=$(git -C "$PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
[ "$CUR" = "$DEFAULT" ] || fail "$PROJECT is on '$CUR', expected default branch '$DEFAULT'"
[ -z "$(git -C "$PROJECT" status --porcelain 2>/dev/null)" ] || fail "$PROJECT has a dirty working tree; refusing to merge into it"

git -C "$PROJECT" merge-base --is-ancestor "$DEFAULT" "$BRANCH" \
  || fail "REFUSED: $BRANCH is not a fast-forward of $DEFAULT (it has diverged) - rebase the builder's branch first"

git -C "$PROJECT" merge --ff-only "$BRANCH" || fail "fast-forward merge failed"
echo "merged: $ID -> $DEFAULT in $PROJECT (fast-forward)"
