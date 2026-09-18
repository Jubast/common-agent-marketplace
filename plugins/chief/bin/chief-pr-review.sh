#!/usr/bin/env bash
# chief-pr-review.sh - post an already-written review to a task's PR/MR.
# This script does no reviewing itself: chief runs the `reviewer` skill
# in-conversation, forms its verdict, then calls this to post the text.
#
# --file/--line attach the comment to a specific line in the diff instead of
# posting it top-level - only valid with --comment, since a review verdict
# (--request-changes) is a property of the whole review, not one line. To
# flag several specific lines and then request changes: one --comment
# --file --line call per finding, then a final --request-changes with no
# file/line to close it out.
#
# Usage: chief-pr-review.sh <id> --comment "<body>" [--file <path> --line <N>]
#        chief-pr-review.sh <id> --request-changes "<body>"
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/chief-paths.sh"
. "$CHIEF_ROOT/bin/lib/chief-meta.sh"
. "$CHIEF_ROOT/bin/lib/chief-pr-provider.sh"

fail() { echo "chief-pr-review: $*" >&2; exit 1; }

USAGE="usage: chief-pr-review.sh <id> --comment|--request-changes \"<body>\" [--file <path> --line <N>]"

ID=${1:-}
[ -n "$ID" ] || fail "$USAGE"
chief_meta_exists "$ID" || fail "no such task: $ID"
shift

VERDICT=""
BODY=""
FILE=""
LINE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --comment) VERDICT=comment; BODY=${2:-}; shift 2 ;;
    --request-changes) VERDICT=request-changes; BODY=${2:-}; shift 2 ;;
    --file) FILE=${2:-}; shift 2 ;;
    --line) LINE=${2:-}; shift 2 ;;
    *) fail "$USAGE" ;;
  esac
done
[ -n "$VERDICT" ] || fail "$USAGE"
[ -n "$BODY" ] || fail "review body must not be empty"

if [ -n "$FILE" ] || [ -n "$LINE" ]; then
  [ -n "$FILE" ] && [ -n "$LINE" ] || fail "--file and --line must be given together"
  case "$LINE" in
    ''|*[!0-9]*) fail "--line must be a positive integer, got: $LINE" ;;
  esac
  [ "$VERDICT" = "comment" ] || fail "--file/--line only work with --comment - a review verdict applies to the whole PR, not one line. Post the inline comment with --comment, then a separate --request-changes with no --file/--line to close it out."
fi

URL=$(chief_meta_require "$ID" pr_url)
PROVIDER=$(chief_meta_require "$ID" pr_provider)
chief_pr_load_provider "$PROVIDER" || exit 1

if [ -n "$FILE" ]; then
  pr_review_line "$URL" "$FILE" "$LINE" "$BODY"
  echo "commented: $ID ($FILE:$LINE)"
else
  pr_review "$URL" "$VERDICT" "$BODY"
  echo "reviewed: $ID ($VERDICT)"
fi
