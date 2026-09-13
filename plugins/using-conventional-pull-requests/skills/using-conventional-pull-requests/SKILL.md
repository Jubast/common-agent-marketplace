---
name: using-conventional-pull-requests
description: Use when about to open a pull request in this repository - teaches when the conventional-pull-requests skill is required over a plain `gh pr create`.
---

If the user asks to open or create a pull request, or invokes any
PR-creation command, you MUST use the `conventional-pull-requests` skill
instead of running `gh pr create` directly with an arbitrary title/body.

- **conventional-pull-requests** — gathers the branch's commits and diff,
  drafts a conventional-commit-style title and a structured body (`feat:`,
  `fix:`, `docs:`, etc.), and creates the PR with the `gh` CLI.

See that skill for its full procedure.
