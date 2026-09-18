#!/usr/bin/env bash
# chief-teardown.sh - kills the terminal, removes the worktree, marks the
# backlog item done. A SHIP task refuses unless its branch has landed on the
# default branch, unless --abandon force-discards it. A SCOUT task discards
# unconditionally - its deliverable is the report at $DATA/<id>/report.md,
# outside the worktree, untouched either way.
#
# A ship whose PR was squash- or rebase-merged has a branch that's never a
# local ancestor of the default branch (both methods create new commits
# with no ancestry back to it) - so when the ancestry check fails, this
# also asks the provider directly whether the recorded PR is merged before
# refusing.
#
# Usage: chief-teardown.sh <id> [--abandon]
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"
. "$CHIEF_ROOT/bin/lib/chief-backend.sh"
. "$CHIEF_ROOT/bin/lib/chief-pr-provider.sh"

fail() { echo "chief-teardown: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-teardown.sh <id> [--abandon]"
chief_meta_exists "$ID" || fail "no such task: $ID"
shift

ABANDON=0
case "${1:-}" in
  --abandon) ABANDON=1; shift ;;
  "") ;;
  *) fail "unknown argument: $1" ;;
esac

PROJECT=$(chief_meta_require "$ID" project)
BRANCH=$(chief_meta_require "$ID" branch)
WORKTREE=$(chief_meta_require "$ID" worktree)
MODE=$(chief_meta_get "$ID" mode 2>/dev/null || true)

_chief_discard() {  # <reason-for-the-echo-line>
  backend_kill "$ID"
  git -C "$PROJECT" worktree remove --force "$WORKTREE" 2>/dev/null || rm -rf "$WORKTREE"
  git -C "$PROJECT" branch -D "$BRANCH" >/dev/null 2>&1 || true
  chief_meta_set "$ID" status torn-down
  "$CHIEF_ROOT/bin/chief-backlog.sh" done "$ID" 2>/dev/null || true
  echo "torn down: $ID ($1)"
}

if [ "$MODE" = "scout" ]; then
  _chief_discard "scout, discarded - its deliverable is the report, not this worktree"
  exit 0
fi

if [ "$ABANDON" -eq 1 ]; then
  _chief_discard "abandoned - work had not landed, discarded on the operator's explicit instruction"
  exit 0
fi

git -C "$PROJECT" show-ref --verify --quiet "refs/heads/$BRANCH" \
  || fail "branch $BRANCH no longer exists in $PROJECT - refusing without proof it landed"

DEFAULT=$(git -C "$PROJECT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || true
[ -n "$DEFAULT" ] || DEFAULT=$(git -C "$PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null || echo main)

if ! git -C "$PROJECT" merge-base --is-ancestor "$BRANCH" "$DEFAULT" 2>/dev/null; then
  PR_URL=$(chief_meta_get "$ID" pr_url 2>/dev/null || true)
  PR_PROVIDER=$(chief_meta_get "$ID" pr_provider 2>/dev/null || true)
  if [ -n "$PR_URL" ] && [ -n "$PR_PROVIDER" ] \
    && chief_pr_load_provider "$PR_PROVIDER" 2>/dev/null && pr_merged "$PR_URL"; then
    _chief_discard "landed via merged PR $PR_URL ($PR_PROVIDER) - not a local ancestor (squash/rebase merge), confirmed with the provider instead"
    exit 0
  fi
  fail "REFUSED: $BRANCH is not reachable from $DEFAULT - the work has not landed. Run chief-local-merge.sh $ID --confirm first, or merge it by hand, then retry. If it was merged via chief-pr-merge.sh, that lands on the remote's default branch - fetch/update $DEFAULT locally (e.g. git -C $PROJECT fetch origin $DEFAULT && git -C $PROJECT merge --ff-only origin/$DEFAULT) and retry. To discard it instead of landing it, use --abandon."
fi

_chief_discard "landed on $DEFAULT, worktree removed"
