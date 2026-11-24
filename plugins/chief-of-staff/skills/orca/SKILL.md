---
name: orca
description: Orca commands for Chief's workers. Load with chief-of-staff:helpers when the backend is Orca.
user-invocable: false
---

# Workers on Orca

The `using-orca` skill is Orca's own guide. Pass `--json` and read stdout;
stderr carries a banner.

- **Spawn**
  1. If `orca repo list --json` lacks the project: `orca repo add --path <project>`.
  2. `orca worktree create --repo path:<project> --name <id> --parent-worktree path:<project> --json`.
     Orca picks the path (`.result.worktree.path`) and branch; rename it:
     `git -C <worktree> branch -m <branch>`.
  3. `orca terminal close --worktree path:<worktree> --all`, then
     `orca terminal create --worktree path:<worktree> --command '<worker command>' --json`.
     The handle is `.result.handle`.
  4. Record the worktree and handle in `meta`.
- **Send**: `orca terminal send --terminal <handle> --text "<line>" --enter`.
- **Look**: `orca terminal read --terminal <handle> --screen --json`. A
  folder-trust dialog on the screen: accept it with
  `orca terminal send --terminal <handle> --enter`.
- **Teardown**: `orca terminal close --worktree path:<worktree> --all`,
  `orca worktree rm --worktree path:<worktree> --force`, then
  `git -C <project> branch -D <branch>`.
