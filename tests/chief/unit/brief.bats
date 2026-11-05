# brief.sh's chief_brief_strip_section helper.

setup() {
  load ../lib/common
  . "$BIN/lib/brief.sh"
  BRIEF="$BATS_TEST_TMPDIR/brief.md"
}

@test "strip_section: removes a section that runs to EOF and keeps the rest" {
  printf '%s\n' "# Task" "original intent" "" "# Relaunch checkpoint (T1)" "first progress note" > "$BRIEF"
  chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
  assert_equal "$(cat "$BRIEF")" "$(printf '%s\n' "# Task" "original intent")"
}

@test "strip_section: repeated strip and append leaves a single section" {
  printf '%s\n' "# Task" "original intent" "" "# Relaunch checkpoint (T1)" "first progress note" \
    "" "# Relaunch checkpoint (T2)" "second progress note" > "$BRIEF"
  chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
  printf '\n# Relaunch checkpoint (T3)\nthird progress note\n' >> "$BRIEF"
  assert_equal "$(cat "$BRIEF")" "$(printf '%s\n' "# Task" "original intent" "" "" "# Relaunch checkpoint (T3)" "third progress note")"
}

@test "strip_section: stops at the next top-level heading and keeps it" {
  printf '%s\n' "# Task" "original intent" "" "# Relaunch checkpoint (T1)" "progress note" \
    "" "# Promoted to a builder (T2)" "promotion notice" > "$BRIEF"
  chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
  assert_equal "$(cat "$BRIEF")" "$(printf '%s\n' "# Task" "original intent" "" "# Promoted to a builder (T2)" "promotion notice")"
}

@test "strip_section: leaves the file unchanged when the section is absent" {
  printf '%s\n' "# Task" "original intent" > "$BRIEF"
  cp "$BRIEF" "$BRIEF.orig"
  chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
  run diff "$BRIEF.orig" "$BRIEF"
  assert_success
}
