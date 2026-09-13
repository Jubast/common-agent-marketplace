# conventional-pull-requests

Opens pull requests with conventional-commit-style titles and structured
bodies, gathering the change set from the branch's commits and diff against
its base branch.

## What's in here

- `.claude-plugin/plugin.json` — the plugin manifest, read directly by
  both Claude Code and Copilot CLI.
- `skills/conventional-pull-requests/` — the skill: a single `SKILL.md`.

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
