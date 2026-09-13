# conventional-commits

Commits changes using micro commits with conventional commit messages,
grouping related files into logical commits. Enforced via a `SessionStart`
hook that force-injects a reminder to use the skill, so the guidance
doesn't depend on the model choosing to read a skill file.

## What's in here

- `.claude-plugin/plugin.json` — the plugin manifest, read directly by
  both Claude Code and Copilot CLI.
- `skills/conventional-commits/` — the skill: a single `SKILL.md`.
- `skills/using-conventional-commits/` — a short trigger skill pointing at
  `conventional-commits` for its full commit procedure.
- `hooks/` — the `SessionStart` hook, which force-injects
  `skills/using-conventional-commits/SKILL.md` as `additionalContext` on
  every session start, so the guidance doesn't depend on the model
  choosing to read a skill file. Claude Code only, and only a native
  plugin install registers it — tools that just copy skill files (e.g.
  `npx skills add`) drop `hooks/`.

## Provenance

`skills/conventional-commits/SKILL.md` originated as a copy of
[this gist](https://gist.github.com/rvanbaalen/50769263f3b96f58c27aed4d4e11dc54)
([revision `45222e19`](https://gist.githubusercontent.com/rvanbaalen/50769263f3b96f58c27aed4d4e11dc54/raw/45222e19ae74a9307555472a46cd221f446ce457/SKILL.md)).
Locally, the upstream's per-commit `Approve? yes/no` gate was removed —
this version groups and commits using its own judgment, surfacing
feedback-driven adjustments only after the fact. See git history for the
diff from the gist revision above.

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
