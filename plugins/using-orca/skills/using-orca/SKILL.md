---
name: using-orca
description: Use when working in an environment where the orca CLI is available (check `orca status`), especially before dispatching an agent into a worktree or isolating work - teaches when to prefer orca-cli over generic git-worktree/Agent-tool isolation.
---

## Detecting Orca

Before defaulting to generic isolation, check whether this environment is
Orca-managed:

```bash
command -v orca >/dev/null 2>&1 && orca status --json >/dev/null 2>&1
```

If that succeeds, Orca is running and tracking this workspace — prefer its
tooling over ad hoc alternatives for the rest of this session.

## Prefer orca-cli over generic isolation

`orca-cli` is a separate, more detailed skill (installed alongside this one
in Orca-managed devcontainers). When Orca is available, check it — and favor
its commands — before reaching for:

- the Agent tool's `isolation: "worktree"` option,
- a raw `git worktree add`,
- or an ad hoc background PTY/process for a "spawned" or "dispatched" agent.

Those alternatives create work that's invisible to the user outside this
session. An Orca child worktree is tracked, inspectable, and attachable from
the Orca app.

## Core dispatch command

```bash
orca worktree create --agent <agent-id> --prompt "<task>" --json
```

This spawns a real, visible child worktree with an agent running in it —
not an ephemeral background process the user has no way to see or resume.

For the full range of orca-cli capabilities (terminals, folder contexts,
repos, automations, artifacts, skill sharing, worktree comments, the
embedded browser), consult the `orca-cli` skill directly — this skill is
just the trigger that gets you to check for it.
