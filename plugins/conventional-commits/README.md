# conventional-commits

Commits changes using micro commits with conventional commit messages,
grouping related files into logical commits.

## What's in here

- `.claude-plugin/plugin.json` — the plugin manifest, read directly by
  both Claude Code and Copilot CLI.
- `skills/conventional-commits/` — the skill: a single `SKILL.md`.

## Provenance

The `skills/conventional-commits/SKILL.md` file originated as a copy of:

- Source: [gist by rvanbaalen](https://gist.github.com/rvanbaalen/50769263f3b96f58c27aed4d4e11dc54)
- Raw file fetched: [`SKILL.md` at revision `45222e19ae74a9307555472a46cd221f446ce457`](https://gist.githubusercontent.com/rvanbaalen/50769263f3b96f58c27aed4d4e11dc54/raw/45222e19ae74a9307555472a46cd221f446ce457/SKILL.md)

Besides the plugin scaffolding (`plugin.json`, this README) added locally
to fit this marketplace's conventions, the workflow was changed from the
original: the upstream skill proposes each commit group with an
`Approve? yes/no` prompt and waits for the user to confirm before staging
and committing it. That approval gate was removed — this version has the
agent group the changes and commit each group directly using its own
judgment, only surfacing feedback-driven adjustments (wrong grouping,
wrong message) after the fact rather than gating on upfront sign-off. See
git history for the exact diff from the upstream gist revision above.

## Using this plugin

Install the marketplace, then this plugin, from a Claude Code session:

```
/plugin marketplace add <org>/<repo>
/plugin install conventional-commits
```

Copilot CLI equivalent:

```
copilot plugin marketplace add <org>/<repo>
copilot plugin install conventional-commits
```

(Replace `<org>/<repo>` with this repository's path once it's pushed to
GitHub.)
