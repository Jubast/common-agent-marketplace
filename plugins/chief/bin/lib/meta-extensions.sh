#!/usr/bin/env bash
# meta-extensions.sh - helpers derived from a task's meta (and the data layout).
# Sourced by scripts that already sourced paths.sh and meta.sh.

# chief_task_workspace <id> -> the backend's name for the task's workspace.
# herdr records it as label= at spawn; older herdr tasks were chief-<id>, Orca's
# worktree is named <id>. Prints nothing when the backend has none (mock).
chief_task_workspace() {
  local id=$1 label endpoint
  label=$(chief_meta_get "$id" label 2>/dev/null || true)
  if [ -z "$label" ]; then
    endpoint=$(chief_meta_get "$id" endpoint 2>/dev/null || true)
    case "$endpoint" in
      herdr:*) label="chief-$id" ;;
      orca:*) label=$id ;;
    esac
  fi
  printf '%s' "$label"
}

# chief_task_where <id> -> indented key: value lines for the task's workspace,
# branch, worktree, brief and report.
chief_task_where() {
  local id=$1 ws
  ws=$(chief_task_workspace "$id")
  [ -z "$ws" ] || printf '  workspace: %s\n' "$ws"
  printf '  branch: %s\n' "$(chief_meta_get "$id" branch 2>/dev/null || true)"
  printf '  worktree: %s\n' "$(chief_meta_get "$id" worktree 2>/dev/null || true)"
  printf '  brief: %s\n' "$DATA/$id/brief.md"
  printf '  report: %s\n' "$DATA/$id/report.md"
}
