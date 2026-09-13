---
name: using-conventional-commits
description: Use when about to commit changes in this repository - teaches when the conventional-commits skill is required over a plain `git commit`.
---

If the user asks to commit changes, or invokes `/commit`, you MUST use the
`conventional-commits` skill instead of running `git commit` directly with an
arbitrary message.

- **conventional-commits** — analyzes the diff, groups related files, and
  commits each group with a conventional commit message (`feat:`, `fix:`,
  `docs:`, etc.).

See that skill for its full procedure.
