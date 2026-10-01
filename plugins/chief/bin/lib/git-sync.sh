#!/usr/bin/env bash
# git-sync.sh - best-effort freshening of a project's default-branch checkout
# against origin. Never fails the caller: every command inside is guarded,
# and a skip is reported with a one-line note to stderr instead of an error.

# chief_sync_default_branch <project-dir>
#   fetch origin, then fast-forward the local default branch onto it - but
#   only when the checkout is currently ON that default branch with a clean
#   working tree. Otherwise skips silently (a note to stderr). Never touches
#   a task's own branch or in-progress work. Writes one progress line per
#   step to stderr so a backend pane running it shows what happened.
chief_sync_default_branch() {
  local project_dir=$1

  echo "chief-sync: fetching origin in $project_dir" >&2
  git -C "$project_dir" fetch origin >/dev/null 2>&1 \
    || echo "chief-sync: fetch failed in $project_dir" >&2

  local default
  default=$(git -C "$project_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || true
  [ -n "$default" ] || default=$(git -C "$project_dir" symbolic-ref --quiet --short HEAD 2>/dev/null || echo main)

  local current
  current=$(git -C "$project_dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  if [ -z "$current" ] || [ "$current" != "$default" ]; then
    echo "chief-sync: skipped - $project_dir is not on $default" >&2
    return 0
  fi

  if [ -n "$(git -C "$project_dir" status --porcelain 2>/dev/null)" ]; then
    echo "chief-sync: skipped - $project_dir working tree is not clean" >&2
    return 0
  fi

  if git -C "$project_dir" merge --ff-only "origin/$default" >/dev/null 2>&1; then
    echo "chief-sync: $default is up to date with origin/$default" >&2
  else
    echo "chief-sync: skipped - could not fast-forward $default from origin in $project_dir" >&2
  fi
  return 0
}
