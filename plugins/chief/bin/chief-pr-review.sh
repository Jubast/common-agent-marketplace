#!/usr/bin/env bash
# chief-pr-review.sh - post an already-written review to a task's PR/MR.
# This script does no reviewing itself: chief runs the `reviewer` skill
# in-conversation, forms its verdict, then calls this to post the text.
#
# Usage: chief-pr-review.sh <id> --comment "<body>"
#        chief-pr-review.sh <id> --request-changes "<body>"
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"
. "$CHIEF_ROOT/bin/lib/chief-pr-provider.sh"

fail() { echo "chief-pr-review: $*" >&2; exit 1; }

ID=${1:-}
[ -n "$ID" ] || fail "usage: chief-pr-review.sh <id> --comment|--request-changes \"<body>\""
chief_meta_exists "$ID" || fail "no such task: $ID"
shift

case "${1:-}" in
  --comment) VERDICT=comment; BODY=${2:-} ;;
  --request-changes) VERDICT=request-changes; BODY=${2:-} ;;
  *) fail "usage: chief-pr-review.sh <id> --comment|--request-changes \"<body>\"" ;;
esac
[ -n "$BODY" ] || fail "review body must not be empty"

URL=$(chief_meta_require "$ID" pr_url)
PROVIDER=$(chief_meta_require "$ID" pr_provider)
chief_pr_load_provider "$PROVIDER" || exit 1

pr_review "$URL" "$VERDICT" "$BODY"
echo "reviewed: $ID ($VERDICT)"
