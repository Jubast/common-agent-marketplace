#!/usr/bin/env bash
# chief-teardown.sh - refuses unless the task's branch is reachable from the
# project's default branch (i.e. chief-merge.sh already landed it, or a human
# merged it some other way). Only then: kill the terminal, remove the
# worktree, mark the backlog item done. Never discards anything by itself -
# there is deliberately no --force here.
#
# Usage: chief-teardown.sh <id>
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"
. "$CHIEF_ROOT/bin/lib/chief-backend.sh"

fail() { echo "chief-teardown: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-teardown.sh <id>"
chief_meta_exists "$ID" || fail "no such task: $ID"

PROJECT=$(chief_meta_require "$ID" project)
BRANCH=$(chief_meta_require "$ID" branch)
WORKTREE=$(chief_meta_require "$ID" worktree)

git -C "$PROJECT" show-ref --verify --quiet "refs/heads/$BRANCH" \
  || fail "branch $BRANCH no longer exists in $PROJECT - refusing without proof it landed"

DEFAULT=$(git -C "$PROJECT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || true
[ -n "$DEFAULT" ] || DEFAULT=$(git -C "$PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null || echo main)

if ! git -C "$PROJECT" merge-base --is-ancestor "$BRANCH" "$DEFAULT" 2>/dev/null; then
  fail "REFUSED: $BRANCH is not reachable from $DEFAULT - the work has not landed. Run chief-merge.sh first, or merge it by hand, then retry."
fi

backend_kill "$ID"
git -C "$PROJECT" worktree remove --force "$WORKTREE" 2>/dev/null || rm -rf "$WORKTREE"
git -C "$PROJECT" branch -D "$BRANCH" >/dev/null 2>&1 || true

chief_meta_set "$ID" status torn-down
"$CHIEF_ROOT/bin/chief-backlog.sh" done "$ID" 2>/dev/null || true

echo "torn down: $ID (landed on $DEFAULT, worktree removed)"
