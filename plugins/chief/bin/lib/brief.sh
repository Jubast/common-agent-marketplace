#!/usr/bin/env bash
# brief.sh - helpers for updating a task's data/<id>/brief.md in place.
# Sourced by scripts that already sourced paths.sh (needs $DATA).

# chief_brief_strip_section <brief_file> <heading_prefix> - drops any
# existing top-level section whose heading starts with heading_prefix (from
# that heading line up to the next top-level "# " heading, or EOF). Callers
# use this before appending a fresh version of the same section, so a
# repeat update (e.g. a second relaunch) replaces what the builder is told
# instead of stacking a changelog of past notes behind it.
chief_brief_strip_section() {
  local file=$1 prefix=$2
  [ -f "$file" ] || return 0
  local tmp
  tmp=$(mktemp "$(dirname "$file")/.brief.XXXXXX")
  awk -v prefix="$prefix" '
    index($0, prefix) == 1 { skip=1 }
    /^# / && index($0, prefix) != 1 { skip=0 }
    !skip
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}
