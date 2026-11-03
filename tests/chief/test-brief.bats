# brief.sh's chief_brief_strip_section helper.

setup() {
  load lib/common
  . "$CHIEF_BIN/lib/brief.sh"
  BRIEF="$BATS_TEST_TMPDIR/brief.md"
}

@test "strips a checkpoint section that runs to EOF and leaves the rest untouched" {
  printf '%s\n' "# Task" "original intent" "" "# Relaunch checkpoint (T1)" "first progress note" > "$BRIEF"
  chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
  assert_equal "$(grep -c '^# Relaunch checkpoint' "$BRIEF")" 0
  run cat "$BRIEF"
  assert_output --partial "original intent"
}

@test "a repeat strip+append collapses to a single section, not a stack" {
  printf '%s\n' "# Task" "original intent" "" "# Relaunch checkpoint (T1)" "first progress note" \
    "" "# Relaunch checkpoint (T2)" "second progress note" > "$BRIEF"
  chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
  printf '\n# Relaunch checkpoint (T3)\nthird progress note\n' >> "$BRIEF"
  assert_equal "$(grep -c '^# Relaunch checkpoint' "$BRIEF")" 1
  run cat "$BRIEF"
  assert_output --partial "third progress note"
  refute_output --partial "first progress note"
  refute_output --partial "second progress note"
}

@test "strips a checkpoint section followed by another top-level heading, keeping it" {
  printf '%s\n' "# Task" "original intent" "" "# Relaunch checkpoint (T1)" "progress note" \
    "" "# Promoted to a ship task (T2)" "ship notice" > "$BRIEF"
  chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
  run cat "$BRIEF"
  refute_output --partial "progress note"
  assert_output --partial "ship notice"
}

@test "a no-op strip when the section is absent leaves the file unchanged" {
  printf '%s\n' "# Task" "original intent" > "$BRIEF"
  chief_brief_strip_section "$BRIEF" "# Relaunch checkpoint"
  run cat "$BRIEF"
  assert_output --partial "original intent"
}
