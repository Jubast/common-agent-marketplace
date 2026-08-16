---
name: clean-code
description: 'Use only when Robert C. Martin''s Clean Code principles are explicitly invoked for C#/.NET code — phrases like "clean code", "apply clean code principles", "clean-code skill", "review this for clean code", "is this SRP-compliant", or "Uncle Bob" — or a direct ask to check naming, functions, comments, formatting, error handling, classes, boundaries, tests, or code smells against the book. Covers design, writing, and review of C#/.NET code against a curated subset of the book (excludes the concurrency chapter and its case-study chapters). Does NOT trigger on generic "review this code" or "write a function that..." requests with no Clean Code framing — the code-review, simplify, and test-driven-development skills already cover those where available.'
---

# Clean Code for C#/.NET

## Purpose

Apply the principles from Robert C. Martin's *Clean Code*, translated
into C#/.NET idiom, at three different moments: shaping a design before
code exists, writing code, and reviewing code that already exists. This
skill targets C#/.NET only, and covers a curated subset of the book —
see "What's covered" below.

## When to use this skill

Trigger **only on explicit invocation** — the user (or another skill)
names Clean Code, Uncle Bob, or one of this skill's specific topics
directly: "apply clean code principles here", "review this for clean
code", "is this class SRP-compliant?", "does this method have any Clean
Code smells?". Do **not** trigger on a generic "review this code" or
"write a function that..." request that never mentions Clean Code —
those are already covered by the `code-review`, `simplify`, and
`test-driven-development` skills where those are available, and this
skill deliberately doesn't compete with them for that trigger surface.

## What's covered

Ten curated topics, each with its own reference file — read only the
ones relevant to the current task, not all ten every time:

- [naming.md](references/naming.md) — meaningful, pronounceable, unambiguous names
- [functions.md](references/functions.md) — small functions, few arguments, one thing
- [comments.md](references/comments.md) — when a comment is earning its keep
- [formatting.md](references/formatting.md) — vertical/horizontal layout, `.editorconfig`
- [error-handling.md](references/error-handling.md) — exceptions, nulls, exception context
- [objects-and-data-structures.md](references/objects-and-data-structures.md) — objects vs. data, Law of Demeter
- [classes.md](references/classes.md) — SRP, cohesion, dependency inversion
- [boundaries.md](references/boundaries.md) — wrapping third-party code, learning tests
- [unit-tests.md](references/unit-tests.md) — F.I.R.S.T., one concept per test
- [smells.md](references/smells.md) — a curated code-smell checklist

**Not covered:** the book's concurrency chapter (its Java thread-pool
patterns are dated and not directly actionable) and its multi-chapter
case-study walkthroughs. If a task genuinely needs concurrency guidance,
say so explicitly rather than stretching this skill's topics to cover
it.

## How to apply this skill

Three modes — pick based on what's actually being asked.

### Design mode

Before writing new code, apply [classes.md](references/classes.md)
(SRP, cohesion) and [boundaries.md](references/boundaries.md) to shape
the class/module structure — what responsibilities exist, where the
seams and abstractions go. This complements, and doesn't replace,
`test-driven-development`.

### Write mode

While producing code, apply [naming.md](references/naming.md),
[functions.md](references/functions.md),
[comments.md](references/comments.md),
[formatting.md](references/formatting.md), and
[error-handling.md](references/error-handling.md) as the code is
written, not as an afterthought pass.

### Review mode

When asked to review existing code or a diff against Clean Code:

1. Identify which of the ten topics are actually implicated by the code
   under review, and read only those reference files.
2. Evaluate the code against each relevant topic's rules.
3. Report findings using the `ReportFindings` tool: one finding per
   violation, ranked most-severe first. Each finding needs `file`,
   `line`, `summary` (one-sentence statement of the defect), and
   `failure_scenario` (a concrete example of the problem this causes).
   Set `category` to the matching topic slug — `naming`, `functions`,
   `comments`, `formatting`, `error-handling`,
   `objects-and-data-structures`, `classes`, `boundaries`,
   `unit-tests`, or `smells`.
4. If the code has no violations, call `ReportFindings` with an empty
   `findings` array rather than skipping the call.

If the `ReportFindings` tool isn't available in the current session, fall
back to emitting the same fields (file, line, summary, failure scenario,
category) as a severity-ranked markdown list, most-severe first — or an
explicit "no violations found" line when the code is clean.

## Output

Design/write mode: code and structure that reflect the relevant
principles, applied as part of producing the work — no separate report.
Review mode: a single `ReportFindings` call listing every violation
found (or an empty list if the code is clean) — or, when that tool isn't
available, the same findings as a severity-ranked markdown list.
