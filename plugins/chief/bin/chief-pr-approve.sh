#!/usr/bin/env bash
# chief-pr-approve.sh - submit an approving review/vote on a task's PR/MR.
#
# Usage: chief-pr-approve.sh <id>
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"
. "$CHIEF_ROOT/bin/lib/chief-pr-provider.sh"

fail() { echo "chief-pr-approve: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-pr-approve.sh <id>"
chief_meta_exists "$ID" || fail "no such task: $ID"

URL=$(chief_meta_require "$ID" pr_url)
PROVIDER=$(chief_meta_require "$ID" pr_provider)
chief_pr_load_provider "$PROVIDER" || exit 1

pr_approve "$URL"
echo "approved: $ID -> $URL"
