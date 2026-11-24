---
name: herdr
description: herdr commands for Chief's workers. Load with chief-of-staff:helpers when the backend is herdr.
user-invocable: false
---

# Workers on herdr

`herdr --skill` is herdr's own guide. Each command replies with JSON.

- **Spawn**
  1. `herdr worktree create --cwd <project> --branch <branch> --path <chief-home>/worktrees/<id> --label <id> --trust-repository --no-focus`.
     The pane is `.result.root_pane.pane_id` (e.g. `w2:p1`); its workspace is
     the part before `:`.
  2. `herdr agent start <id> --kind claude --pane <pane> -- <claude args>`:
     the worker command without the leading `claude`. `agent_not_ready` is
     fine; on `agent_pane_busy` retry after a second.
  3. Record the pane in `meta`.
- **Send**: `herdr agent prompt <id> "<line>"`.
- **Look**: `herdr agent read <id>` shows the screen, `herdr agent get <id>`
  the status. A folder-trust dialog on the screen: accept it with
  `herdr agent send-keys <id> enter`.
- **Teardown**: `herdr workspace close <workspace>`, then
  `git -C <project> worktree remove --force <worktree>` and
  `git -C <project> branch -D <branch>`.
