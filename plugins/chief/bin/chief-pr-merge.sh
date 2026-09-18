#!/usr/bin/env bash
# chief-pr-merge.sh - merge a task's already-opened PR/MR, across whichever
# provider it was opened against. Requires --confirm - only pass it once the
# operator has explicitly said to merge <id>'s PR. Defaults to --squash,
# applied uniformly regardless of provider. For a local-only fast-forward
# merge with no PR at all, use chief-local-merge.sh instead.
#
# Usage: chief-pr-merge.sh <id> --confirm [--squash|--merge|--rebase]
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"
. "$CHIEF_ROOT/bin/lib/chief-pr-provider.sh"

fail() { echo "chief-pr-merge: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-pr-merge.sh <id> --confirm [--squash|--merge|--rebase]"
chief_meta_exists "$ID" || fail "no such task: $ID"
shift

METHOD=""
CONFIRMED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm) CONFIRMED=1; shift ;;
    --squash|--merge|--rebase) METHOD=$1; shift ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[ "$CONFIRMED" -eq 1 ] || fail "refusing to merge without --confirm - only pass it once the operator has explicitly said to merge $ID's PR in this conversation"
METHOD="${METHOD:---squash}"

URL=$(chief_meta_require "$ID" pr_url)
PROVIDER=$(chief_meta_require "$ID" pr_provider)
chief_pr_load_provider "$PROVIDER" || exit 1

pr_merge "$URL" "$METHOD" || fail "merge failed"

echo "merged: $ID via $PROVIDER PR $URL"
