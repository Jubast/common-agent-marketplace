#!/usr/bin/env bash
# meta.sh - a task's folder and its flat key=value record, <task dir>/meta.
# Sourced by paths.sh and the session hook (needs $TASKS and $ARCHIVE).
#
# A meta file is one key=value pair per line, no quoting, no nesting.
# That's the whole format - deliberately too simple to need a parser.

# chief_task_dir <id> -> the task's folder: under $TASKS, or $ARCHIVE once torn down.
chief_task_dir() {
  if [ ! -d "$TASKS/$1" ] && [ -d "$ARCHIVE/$1" ]; then
    printf '%s/%s' "$ARCHIVE" "$1"
  else
    printf '%s/%s' "$TASKS" "$1"
  fi
}

# chief_task_path <id> <name> -> a file or folder inside the task's folder.
chief_task_path() {
  printf '%s/%s' "$(chief_task_dir "$1")" "$2"
}

# chief_task_archive <id> -> moves the task's folder into $ARCHIVE.
chief_task_archive() {
  mkdir -p "$ARCHIVE"
  mv "$TASKS/$1" "$ARCHIVE/$1"
}

# chief_meta_get <id> <key> -> prints the value, or nothing if absent.
chief_meta_get() {
  local id=$1 key=$2
  local file
  file=$(chief_task_path "$id" meta)
  [ -f "$file" ] || return 1
  awk -F= -v k="$key" '$1==k { sub(/^[^=]*=/, ""); print; found=1 } END { exit !found }' "$file"
}

# chief_meta_set <id> <key> <value> -> upserts one key, preserving the rest.
chief_meta_set() {
  local id=$1 key=$2 value=$3
  local file tmp
  file=$(chief_task_path "$id" meta)
  mkdir -p "$(dirname "$file")"
  tmp=$(mktemp "$(dirname "$file")/.meta.XXXXXX")
  if [ -f "$file" ]; then
    awk -F= -v k="$key" '$1==k { next } { print }' "$file" > "$tmp"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
}

# chief_meta_agent <id> -> agent[:model]; claude for a task that predates agents.
chief_meta_agent() {
  local agent model
  agent=$(chief_meta_get "$1" agent 2>/dev/null) || agent=""
  model=$(chief_meta_get "$1" model 2>/dev/null) || model=""
  printf '%s%s' "${agent:-claude}" "${model:+:$model}"
}

# chief_meta_exists <id>
chief_meta_exists() {
  [ -f "$(chief_task_path "$1" meta)" ]
}

# chief_meta_require <id> <key> -> prints the value or fails loudly.
chief_meta_require() {
  local id=$1 key=$2
  local value
  chief_meta_exists "$id" || {
    echo "error: task $id has no meta record at $(chief_task_path "$id" meta)" >&2
    exit 1
  }
  value=$(chief_meta_get "$id" "$key")
  [ -n "$value" ] || {
    echo "error: task $id meta is missing required key '$key'" >&2
    exit 1
  }
  printf '%s\n' "$value"
}
