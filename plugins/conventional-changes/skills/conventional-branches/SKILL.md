---
name: conventional-branches
description: Name a branch with a conventional type prefix and a short kebab-case description. Use when creating, renaming, or choosing a name for a branch, or invoking any branch-creation command, including branches created by tools or automation.
---

# Naming a Branch

## Important Rules

- One structure for every branch, human-authored or tool/automation-created. No exceptions.
- Name the outcome the commits build toward, not the mechanism.
- NEVER use em dashes, spaces, uppercase, or underscores.

## Format

`<type>/<short-kebab-case-description>`

`type` is one of the `conventional-commits` types: `feat`, `fix`, `docs`,
`style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`. Pick the one
that matches the branch's main change.

If the work is tracked against an issue, fold its number in at the start of
the description.

Examples:
- `feat/dark-mode-toggle`
- `fix/123-checkout-duplicate-submit`
- `docs/update-install-steps`

If the project's `CLAUDE.md`/`AGENTS.md` already defines its own branch
naming, follow that instead.
