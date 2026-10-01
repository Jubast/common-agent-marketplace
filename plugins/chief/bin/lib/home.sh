#!/usr/bin/env bash
# home.sh - default CHIEF_HOME resolution, shared by paths.sh and the hooks.

# chief_default_home -> prints <outermost enclosing git root>/.chief.
# Outermost, so a cwd inside a project checkout (or one of its worktrees)
# nested under the workspace repo resolves to the workspace's .chief, never
# one inside the project. Outside any git repo: <cwd>/.chief.
chief_default_home() {
  local root parent
  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  [ -n "$root" ] || { printf '%s/.chief\n' "$(pwd)"; return 0; }
  while parent=$(git -C "$(dirname "$root")" rev-parse --show-toplevel 2>/dev/null) \
    && [ -n "$parent" ] && [ "$parent" != "$root" ]; do
    root=$parent
  done
  printf '%s/.chief\n' "$root"
}
