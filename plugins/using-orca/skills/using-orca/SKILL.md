---
name: using-orca
description: Use when working in an environment where the orca CLI is available (check `orca status`), especially before dispatching an agent into a worktree or isolating work - teaches when to prefer orca-cli over generic git-worktree/Agent-tool isolation.
---

Check whether Orca is running:

```bash
command -v orca >/dev/null 2>&1 && orca status --json >/dev/null 2>&1
```

If so, prefer the `orca-cli` skill's commands over generic isolation — the
Agent tool's `isolation: "worktree"`, raw `git worktree`, or an ad hoc
background PTY. Those alternatives are invisible to the user outside this
session; an Orca child worktree is tracked and attachable from the Orca app.

Core dispatch command:

```bash
orca worktree create --agent <agent-id> --prompt "<task>" --json
```

See the `orca-cli` skill for the full command reference.
