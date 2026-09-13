# conventional-pull-requests

Opens pull requests (or merge requests) with conventional-commit-style
titles and structured bodies, gathering the change set from the branch's
commits and diff against its base branch — regardless of which hosting
platform or CLI the project uses.

## What's in here

- `.claude-plugin/plugin.json` — the plugin manifest, read directly by
  both Claude Code and Copilot CLI.
- `skills/conventional-pull-requests/` — the main skill: drafts the
  title/body and creates the PR/MR.
- `skills/using-conventional-pull-requests/` — a short trigger skill
  pointing at `conventional-pull-requests` for its full procedure.
- `hooks/` — a `SessionStart` hook that force-injects the trigger skill as
  `additionalContext` on every session start, so the guidance doesn't depend
  on the model choosing to read a skill file.

## Using this plugin

Install the marketplace, then this plugin, from a Claude Code session:

```
/plugin marketplace add <org>/<repo>
/plugin install conventional-pull-requests
```

Copilot CLI equivalent:

```
copilot plugin marketplace add <org>/<repo>
copilot plugin install conventional-pull-requests
```

(Replace `<org>/<repo>` with this repository's path once it's pushed to
GitHub.)

Only a native plugin install registers the hook — tools that just copy skill
files (e.g. `npx skills add`) install the `skills/` directories but silently
drop `hooks/`.
