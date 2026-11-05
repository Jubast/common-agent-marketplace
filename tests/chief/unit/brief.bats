# brief.sh's chief_brief_strip_section helper.

setup() {
  load ../lib/common
  . "$CHIEF_BIN/lib/brief.sh"
  BRIEF="$BATS_TEST_TMPDIR/brief.md"
}

@test "strips a checkpoint section that runs to EOF and leaves the rest untouched" {
  printf '%s\n' "# Task" "original intent" "" "# Relaunch checkpoint (T1)" "first progress note" > "$BRIEF"
  chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
  assert_equal "$(cat "$BRIEF")" "$(printf '%s\n' "# Task" "original intent")"
}

@test "a repeat strip+append collapses to a single section, not a stack" {
  printf '%s\n' "# Task" "original intent" "" "# Relaunch checkpoint (T1)" "first progress note" \
    "" "# Relaunch checkpoint (T2)" "second progress note" > "$BRIEF"
  chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
  printf '\n# Relaunch checkpoint (T3)\nthird progress note\n' >> "$BRIEF"
  assert_equal "$(cat "$BRIEF")" "$(printf '%s\n' "# Task" "original intent" "" "" "# Relaunch checkpoint (T3)" "third progress note")"
}

@test "strips a checkpoint section followed by another top-level heading, keeping it" {
  printf '%s\n' "# Task" "original intent" "" "# Relaunch checkpoint (T1)" "progress note" \
    "" "# Promoted to a builder (T2)" "promotion notice" > "$BRIEF"
  chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
  assert_equal "$(cat "$BRIEF")" "$(printf '%s\n' "# Task" "original intent" "" "# Promoted to a builder (T2)" "promotion notice")"
}

@test "a no-op strip when the section is absent leaves the file unchanged" {
  printf '%s\n' "# Task" "original intent" > "$BRIEF"
  cp "$BRIEF" "$BRIEF.orig"
  chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
  run diff "$BRIEF.orig" "$BRIEF"
  assert_success
}
