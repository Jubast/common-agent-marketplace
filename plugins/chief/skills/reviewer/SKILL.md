---
name: reviewer
description: Use before merging a builder's ship task - review its diff against a short fixed checklist. Also usable by a builder on its own work before reporting done.
---

# Chief: reviewer

A fixed, short checklist - not a pipeline. Run it against the diff between a task's branch and the project's default branch before recommending or performing a merge.

1. **Matches intent.** Read the diff against the task's `## Operator's intent` (in `.chief/data/<id>/brief.md`). Does it do that - nothing more, nothing less?
2. **Code and comment quality.** Code and comments stay short and concise. No comment blocks narrating development decisions, how a problem was investigated, or modification history - that belongs in the commit message, not the file.
3. **Builds/lints/tests clean.** Run whatever this project's own check command is. Don't invent new tooling for this.
4. **No debris.** No leftover debug prints, commented-out code, stray TODOs, or scratch files that shouldn't ship.
5. **Scope discipline.** Nothing was added beyond the brief's spec - a generalization, an unrelated refactor, or extra hardening not asked for should be flagged, not silently kept.
6. **Project docs addressed.** Per `templates/brief-ship.md`'s "Project docs" section: the `done` report either updated the relevant well-known project docs (`README.md`, `AGENTS.md`/`CLAUDE.md`, `ARCHITECTURE.md`, `docs/adr/*.md`, `CONSUMER_GUIDE.md`) for a non-trivial change, or named which ones don't exist in the project. Flag a `done` report that's silent on this instead of assuming it was considered.
7. **Doc quality.** If a doc was touched anywhere in the diff: it reads clearly on its own, stays short and concise, and doesn't narrate development decisions or modification history (that belongs in the commit message, not the doc). Check for content duplicated elsewhere and for dead local links.

Report one of:
- `PASS` - safe to merge.
- `FAIL: <checklist item> - <one-line reason>` for each failed check.

If the task already has a PR/MR open (`pr_url` set), post the verdict to it. For each FAIL you can point at a specific line, post it as an inline comment first: `chief-pr-review.sh <id> --comment "<reason>" --file <path> --line <N>`. Then post the overall verdict with no file/line: `chief-pr-review.sh <id> --comment "<verdict>"` for a PASS, or `chief-pr-review.sh <id> --request-changes "<verdict>"` for a FAIL.
