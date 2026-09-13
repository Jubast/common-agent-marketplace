---
name: using-conventional-pull-requests
description: Use when about to open, create, or update a pull request or merge request in this repository - teaches when the conventional-pull-requests skill is required over doing it directly.
---

If the user asks to open, create, or update a pull request (or merge
request), or invokes any PR/MR-creation or PR/MR-update command, you MUST
use the `conventional-pull-requests` skill instead of doing it directly with
an arbitrary title/body — regardless of which hosting platform or CLI the
project uses (GitHub, GitLab, Bitbucket, Azure DevOps, or otherwise).

- **conventional-pull-requests** — gathers the branch's commits and diff,
  drafts a conventional-commit-style title and a structured body (`feat:`,
  `fix:`, `docs:`, etc.), and creates or updates the PR/MR with the
  project's own tooling.

See that skill for its full procedure.
