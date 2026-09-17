#!/usr/bin/env bash
# chief-pr-state.sh - read-only PR/MR blocker report for a task's open PR.
# Never posts, approves, or merges.
#
# Usage: chief-pr-state.sh <id>
#   Prints one line per blocker the provider can see; nothing when there
#   are none. Exits non-zero only on lookup/usage failure, never because
#   blockers exist.
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"
. "$CHIEF_ROOT/bin/lib/chief-pr-provider.sh"

fail() { echo "chief-pr-state: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-pr-state.sh <id>"
chief_meta_exists "$ID" || fail "no such task: $ID"

URL=$(chief_meta_require "$ID" pr_url)
PROVIDER=$(chief_meta_require "$ID" pr_provider)
chief_pr_load_provider "$PROVIDER" || exit 1

pr_state "$URL"
