# using-orca

Teaches Claude Code to recognize and use the Orca CLI (`orca-cli`) for
worktree and agent-dispatch work in Orca-managed environments.

## What's in here

- `.claude-plugin/plugin.json` — plugin manifest.
- `skills/using-orca/` — a short trigger skill pointing at `orca-cli` for
  the full command reference.
- `hooks/` — a `SessionStart` hook that force-injects the skill as
  `additionalContext` whenever Orca is actually running, so the guidance
  doesn't depend on the model choosing to read a skill file.

## Scope

- Claude Code only — the hook emits Claude Code's hook JSON shape.
- Silent when Orca isn't running (checks `orca status --json` itself).
- A pointer, not a reference — see `orca-cli` for full capabilities.

## Using this plugin

```
/plugin marketplace add <org>/<repo>
/plugin install using-orca
```

Only a native plugin install registers the hook — tools that just copy
skill files (e.g. `npx skills add`) install `skills/using-orca/` but
silently drop `hooks/`.
