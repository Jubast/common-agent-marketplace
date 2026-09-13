# using-conventional-pull-requests

Teaches Claude Code to recognize and require the `conventional-pull-requests`
skill whenever a pull request is opened in this repository.

## What's in here

- `.claude-plugin/plugin.json` — plugin manifest.
- `skills/using-conventional-pull-requests/` — a short trigger skill pointing
  at `conventional-pull-requests` for its full PR-creation procedure.
- `hooks/` — a `SessionStart` hook that force-injects the skill as
  `additionalContext` on every session start, so the guidance doesn't depend
  on the model choosing to read a skill file.

## Scope

- Claude Code only — the hook emits Claude Code's hook JSON shape.
- Always injects — unlike `using-orca`, there's no external tool/state to
  gate on.
- A pointer, not a reference — see `conventional-pull-requests` for the full
  PR-creation procedure.

## Using this plugin

```
/plugin marketplace add <org>/<repo>
/plugin install using-conventional-pull-requests
```

Only a native plugin install registers the hook — tools that just copy skill
files (e.g. `npx skills add`) install
`skills/using-conventional-pull-requests/` but silently drop `hooks/`.
