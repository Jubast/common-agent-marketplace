---
name: using-conventional-pull-requests
description: Use when about to open a pull request or merge request in this repository - teaches when the conventional-pull-requests skill is required over creating one directly.
---

If the user asks to open or create a pull request (or merge request), or
invokes any PR/MR-creation command, you MUST use the
`conventional-pull-requests` skill instead of creating one directly with an
arbitrary title/body — regardless of which hosting platform or CLI the
project uses (GitHub, GitLab, Bitbucket, or otherwise).

- **conventional-pull-requests** — gathers the branch's commits and diff,
  drafts a conventional-commit-style title and a structured body (`feat:`,
  `fix:`, `docs:`, etc.), and creates the PR/MR with the project's own
  tooling.

See that skill for its full procedure.
