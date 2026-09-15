#!/usr/bin/env bash
# chief-meta.sh - read/write flat key=value task records at $STATE/<id>.meta.
# Sourced by scripts that already sourced chief-paths.sh (needs $STATE).
#
# A meta file is one key=value pair per line, no quoting, no nesting.
# That's the whole format - deliberately too simple to need a parser.

# chief_meta_get <id> <key> -> prints the value, or nothing if absent.
chief_meta_get() {
  local id=$1 key=$2
  local file="$STATE/$id.meta"
  [ -f "$file" ] || return 1
  awk -F= -v k="$key" '$1==k { sub(/^[^=]*=/, ""); print; found=1 } END { exit !found }' "$file"
}

# chief_meta_set <id> <key> <value> -> upserts one key, preserving the rest.
chief_meta_set() {
  local id=$1 key=$2 value=$3
  local file="$STATE/$id.meta"
  local tmp
  tmp=$(mktemp "$STATE/.$id.meta.XXXXXX")
  if [ -f "$file" ]; then
    awk -F= -v k="$key" '$1==k { next } { print }' "$file" > "$tmp"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
}

# chief_meta_exists <id>
chief_meta_exists() {
  [ -f "$STATE/$1.meta" ]
}

# chief_meta_require <id> <key> -> prints the value or fails loudly.
chief_meta_require() {
  local id=$1 key=$2
  local value
  chief_meta_exists "$id" || {
    echo "error: task $id has no meta record at $STATE/$id.meta" >&2
    exit 1
  }
  value=$(chief_meta_get "$id" "$key")
  [ -n "$value" ] || {
    echo "error: task $id meta is missing required key '$key'" >&2
    exit 1
  }
  printf '%s\n' "$value"
}
