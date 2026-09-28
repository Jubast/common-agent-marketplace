#!/usr/bin/env bash
# test-brief.sh - brief.sh's chief_brief_strip_section helper.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"
. "$CHIEF_BIN/lib/brief.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BRIEF="$WORK/brief.md"

echo "test-brief:"

printf '%s\n' \
  "# Task" \
  "original intent" \
  "" \
  "# Relaunch checkpoint (T1)" \
  "first progress note" \
  > "$BRIEF"
chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
assert_eq "$(grep -c '^# Relaunch checkpoint' "$BRIEF")" "0" "strips a checkpoint section that runs to EOF"
assert_contains "$(cat "$BRIEF")" "original intent" "leaves the rest of the brief untouched"

printf '%s\n' \
  "# Task" \
  "original intent" \
  "" \
  "# Relaunch checkpoint (T1)" \
  "first progress note" \
  "" \
  "# Relaunch checkpoint (T2)" \
  "second progress note" \
  > "$BRIEF"
chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
{
  echo ""
  echo "# Relaunch checkpoint (T3)"
  echo "third progress note"
} >> "$BRIEF"
assert_eq "$(grep -c '^# Relaunch checkpoint' "$BRIEF")" "1" "a repeat strip+append collapses to a single section, not a stack"
assert_contains "$(cat "$BRIEF")" "third progress note" "the latest note survives"
assert_not_contains "$(cat "$BRIEF")" "first progress note" "an older note is gone"
assert_not_contains "$(cat "$BRIEF")" "second progress note" "an older note is gone"

printf '%s\n' \
  "# Task" \
  "original intent" \
  "" \
  "# Relaunch checkpoint (T1)" \
  "progress note" \
  "" \
  "# Promoted to a ship task (T2)" \
  "ship notice" \
  > "$BRIEF"
chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
assert_not_contains "$(cat "$BRIEF")" "progress note" "strips a checkpoint section followed by another top-level heading"
assert_contains "$(cat "$BRIEF")" "ship notice" "a later, unrelated section is preserved"

printf '%s\n' "# Task" "original intent" > "$BRIEF"
chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
assert_contains "$(cat "$BRIEF")" "original intent" "a no-op strip when the section is absent leaves the file unchanged"

harness_summary
