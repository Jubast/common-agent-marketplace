# using-orca

Teaches Claude Code to recognize and use the Orca CLI (`orca-cli`) for
worktree and agent-dispatch work in Orca-managed environments.

## What's in here

- `.claude-plugin/plugin.json` — the plugin manifest, read directly by
  both Claude Code and Copilot CLI.
- `skills/using-orca/` — the skill: a concise trigger/pointer that teaches
  when to check for Orca and prefer its worktree/dispatch commands over
  generic git-worktree or Agent-tool isolation. It defers to the separately
  installed `orca-cli` skill for the full command reference.
- `hooks/` — a `SessionStart` hook (`hooks.json` + `session-start.sh`) that
  checks whether Orca is actually running (`orca status --json`) and, only
  if so, force-injects the skill's content as `additionalContext` on every
  session start, `/clear`, and `/compact` — so the guidance doesn't depend
  on the model choosing to read a skill file.

## Scope

- **Claude Code only.** The hook emits Claude Code's
  `hookSpecificOutput`/`additionalContext` shape specifically; it doesn't
  branch for other platforms' hook formats.
- **Silent when Orca isn't running.** The hook checks `orca status --json`
  itself (with a short timeout) and emits `{}` — no injected context — if
  Orca isn't present or isn't responding, so it never nags with stale
  advice in a plain devcontainer or local checkout.
- **A pointer, not a reference.** This skill only covers enough to
  recognize Orca and know to check `orca-cli` before defaulting to generic
  worktree isolation. It intentionally doesn't duplicate `orca-cli`'s full
  command surface.

## Using this plugin

Install the marketplace, then this plugin, from a Claude Code session:

```
/plugin marketplace add <org>/<repo>
/plugin install using-orca
```

(Replace `<org>/<repo>` with this repository's path once it's pushed to
GitHub.)

Note: `hooks/` are only registered by Claude Code's/Copilot's native plugin
install flow (`claude plugin marketplace add` + `claude plugin install`).
Tools that only copy skill files (e.g. `npx skills add`) will install the
`skills/using-orca/` content but silently drop the `SessionStart` hook.
