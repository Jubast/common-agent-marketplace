---
name: using-conventional-changes
description: Use when about to commit changes, or open/update a pull request or merge request, in this repository - teaches when the conventional-commits and conventional-pull-requests skills are required over doing either directly.
---

If the user asks to commit changes, or invokes `/commit`, you MUST use the
`conventional-commits` skill instead of running `git commit` directly with
an arbitrary message.

If the user asks to open, create, or update a pull request (or merge
request), or invokes any PR/MR-creation or PR/MR-update command, you MUST
use the `conventional-pull-requests` skill instead of doing it directly
with an arbitrary title/body — regardless of which hosting platform or CLI
the project uses (GitHub, GitLab, Bitbucket, Azure DevOps, or otherwise).

- **conventional-commits** — analyzes the diff, groups related files, and
  commits each group with a conventional commit message (`feat:`, `fix:`,
  `docs:`, etc.), then offers to push and continue into
  conventional-pull-requests.
- **conventional-pull-requests** — gathers the branch's commits and diff,
  drafts a conventional-commit-style title and a structured body, and
  creates or updates the PR/MR with the project's own tooling.

See each skill for its full procedure.
