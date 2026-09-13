# using-conventional-commits

Teaches Claude Code to recognize and require the `conventional-commits` skill
whenever changes in this repository are committed.

## What's in here

- `.claude-plugin/plugin.json` — plugin manifest.
- `skills/using-conventional-commits/` — a short trigger skill pointing at
  `conventional-commits` for its full commit procedure.
- `hooks/` — a `SessionStart` hook that force-injects the skill as
  `additionalContext` on every session start, so the guidance doesn't depend
  on the model choosing to read a skill file.

## Scope

- Claude Code only — the hook emits Claude Code's hook JSON shape.
- Always injects — unlike `using-orca`, there's no external tool/state to
  gate on.
- A pointer, not a reference — see `conventional-commits` for the full
  commit procedure.

## Using this plugin

```
/plugin marketplace add <org>/<repo>
/plugin install using-conventional-commits
```

Only a native plugin install registers the hook — tools that just copy skill
files (e.g. `npx skills add`) install `skills/using-conventional-commits/`
but silently drop `hooks/`.
