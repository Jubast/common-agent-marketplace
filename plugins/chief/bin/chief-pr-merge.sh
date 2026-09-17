#!/usr/bin/env bash
# chief-pr-merge.sh - merge a task's already-opened PR/MR, across whichever
# provider it was opened against. Always operator-invoked; there is no
# yolo/auto-merge in this plugin, on purpose - a human runs this command.
# Replaces chief-merge.sh's old --pr mode (which was GitHub-only); for a
# local-only fast-forward merge with no PR at all, use chief-merge.sh.
#
# Usage: chief-pr-merge.sh <id> [--squash|--merge|--rebase]
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"
. "$CHIEF_ROOT/bin/lib/chief-pr-provider.sh"

fail() { echo "chief-pr-merge: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-pr-merge.sh <id> [--squash|--merge|--rebase]"
chief_meta_exists "$ID" || fail "no such task: $ID"
shift

METHOD=""
case "${1:-}" in
  --squash|--merge|--rebase) METHOD=$1; shift ;;
  "") ;;
  *) fail "unknown argument: $1" ;;
esac

URL=$(chief_meta_require "$ID" pr_url)
PROVIDER=$(chief_meta_require "$ID" pr_provider)
chief_pr_load_provider "$PROVIDER" || exit 1

if [ -n "$METHOD" ]; then
  pr_merge "$URL" "$METHOD" || fail "merge failed"
else
  pr_merge "$URL" || fail "merge failed"
fi

echo "merged: $ID via $PROVIDER PR $URL"
