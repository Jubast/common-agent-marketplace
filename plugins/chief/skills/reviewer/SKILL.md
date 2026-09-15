---
name: reviewer
description: Use before merging a builder's ship task - review its diff against a short fixed checklist. Also usable by a builder on its own work before reporting done. Placeholder checklist; expand as real review needs become clear.
---

# Chief: reviewer

A fixed, short checklist - not a pipeline. Run it against the diff between a task's branch and the project's default branch before recommending or performing a merge.

1. **Matches intent.** Read the diff against the task's `## Operator's intent` (in `.chief/data/<id>/brief.md`). Does it do that - nothing more, nothing less?
2. **Builds/lints/tests clean.** Run whatever this project's own check command is. Don't invent new tooling for this.
3. **No debris.** No leftover debug prints, commented-out code, stray TODOs, or scratch files that shouldn't ship.
4. **Scope discipline.** Nothing was added beyond the brief's spec - a generalization, an unrelated refactor, or extra hardening not asked for should be flagged, not silently kept.

Report one of:
- `PASS` - safe to merge.
- `FAIL: <checklist item> - <one-line reason>` for each failed check.

This is intentionally thin. As real review needs surface (security patterns, project-specific conventions, etc.), add them here rather than building a separate pipeline.
