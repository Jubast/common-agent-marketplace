---
name: using-orca
description: Use when working in an environment where the orca CLI is available (check `orca status`), especially before dispatching an agent, isolating work, or coordinating multiple agents - teaches when orca-cli/orchestration are required over generic git-worktree/Agent-tool isolation.
---

Check whether Orca is running:

```bash
command -v orca >/dev/null 2>&1 && orca status --json >/dev/null 2>&1
```

If so, you MUST use the `orca-cli` and `orchestration` skills instead of
generic alternatives — the Agent tool's `isolation: "worktree"`, raw `git
worktree`, or an ad hoc background PTY. Those are invisible to the user
outside this session; Orca's tooling is tracked and attachable from the app.

- **orca-cli** — worktrees, terminals, artifacts, handoffs:
  ```bash
  orca worktree create --agent <agent-id> --prompt "<task>" --json
  ```
- **orchestration** — supervising workers: threaded messages, task
  dispatch, DAGs, decision gates.

See each skill for its full command reference.
