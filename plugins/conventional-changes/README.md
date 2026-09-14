# conventional-changes

Commits changes using micro commits with conventional commit messages,
then creates or updates a pull/merge request with a conventional-commit-
style title and structured body — the two skills are used back to back in
one workflow, so they ship as a single plugin. Enforced via a
`SessionStart` hook that force-injects a reminder to use them, so the
guidance doesn't depend on the model choosing to read a skill file.

## What's in here

- `.claude-plugin/plugin.json` — the plugin manifest, read directly by
  both Claude Code and Copilot CLI.
- `skills/conventional-commits/` — analyzes the diff, groups related
  files, and commits each group with a conventional commit message, then
  offers to push and continue into `conventional-pull-requests`.
- `skills/conventional-pull-requests/` — gathers the branch's commits and
  diff against the base branch, drafts a conventional-commit-style title
  and structured body, and creates or updates the PR/MR with the
  project's own tooling.
- `skills/using-conventional-changes/` — a short trigger skill pointing
  at both of the above for their full procedures.
- `hooks/` — the `SessionStart` hook, which force-injects
  `skills/using-conventional-changes/SKILL.md` as `additionalContext` on
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

`conventional-commits` and `conventional-pull-requests` previously shipped
as two separate plugins (each with its own trigger skill and
`SessionStart` hook); they were merged here since one workflow uses both
in sequence. See git history for the pre-merge structure.

## Using this plugin

Install the marketplace, then this plugin, from a Claude Code session:

```
/plugin marketplace add <org>/<repo>
/plugin install conventional-changes
```

Copilot CLI equivalent:

```
copilot plugin marketplace add <org>/<repo>
copilot plugin install conventional-changes
```

(Replace `<org>/<repo>` with this repository's path once it's pushed to
GitHub.)
