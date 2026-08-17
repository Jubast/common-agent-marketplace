---
name: clean-architecture
description: 'Use only when Robert C. Martin''s Clean Architecture principles are explicitly invoked for C#/.NET code or solution structure — phrases like "clean architecture", "apply the dependency rule", "hexagonal architecture", "onion architecture", "ports and adapters", "screaming architecture", "is this layered correctly", "Uncle Bob''s architecture", "review architecture boundaries" — or a direct ask to check the dependency rule, SOLID/component principles, entities vs. use cases, interface adapters, boundaries, frameworks-as-details, solution structure, screaming architecture, or testing strategy against the book. Covers design, writing, and review of C#/.NET solution structure and layering against a curated subset of the book (excludes the programming-paradigms chapters, the embedded-architecture chapter, and its case-study chapters). Does NOT trigger on generic "review this code", "write a function that...", or generic new-project scaffolding requests with no Clean Architecture framing — this repo''s code-review, simplify, and test-driven-development skills already cover those where available.'
---

# Clean Architecture for C#/.NET

## Purpose

Apply the principles from Robert C. Martin's *Clean Architecture*,
translated into C#/.NET idiom, at three different moments: shaping a
solution's layering before code exists, writing code within that
layering, and reviewing code or a solution structure that already
exists. This skill targets C#/.NET only, and covers a curated subset of
the book — see "What's covered" below.

## When to use this skill

Trigger **only on explicit invocation** — the user (or another skill)
names Clean Architecture, the Dependency Rule, Uncle Bob, or one of this
skill's specific topics directly: "apply the dependency rule here",
"review this solution's architecture boundaries", "does this follow
Clean Architecture?", "is Domain leaking into Infrastructure?". Do
**not** trigger on a generic "review this code", "write a function
that...", or "scaffold a new .NET project" request that never mentions
Clean Architecture or its vocabulary — those are already covered by this
repository's own `code-review`, `simplify`, and `test-driven-development`
skills, and this skill deliberately doesn't compete with them for that
trigger surface.

## What's covered

Nine curated topics, each with its own reference file — read only the
ones relevant to the current task, not all nine every time:

- [dependency-rule.md](references/dependency-rule.md) — the Dependency Rule, the four circles
- [solid-and-components.md](references/solid-and-components.md) — SOLID and component cohesion/coupling at assembly level
- [entities-and-use-cases.md](references/entities-and-use-cases.md) — business rules layer, request/response models
- [interface-adapters.md](references/interface-adapters.md) — controllers, presenters, gateways, Humble Object
- [boundaries-and-dtos.md](references/boundaries-and-dtos.md) — crossing boundaries, DTOs vs. entities, leakage
- [frameworks-and-details.md](references/frameworks-and-details.md) — the database/web/frameworks as details
- [dotnet-solution-structure.md](references/dotnet-solution-structure.md) — concrete .NET layout, the Main Component
- [screaming-architecture.md](references/screaming-architecture.md) — folder structure that reflects the domain
- [testing-strategy.md](references/testing-strategy.md) — tests as the outermost circle, architecture tests

**Not covered:** the book's programming-paradigms chapters (structured,
object-oriented, functional — scene-setting rather than actionable), its
embedded-architecture chapter (not relevant to typical .NET web/service
work), and its case-study chapters. If a task genuinely needs paradigm-
level or embedded-systems guidance, say so explicitly rather than
stretching this skill's topics to cover it.

## How to apply this skill

Three modes — pick based on what's actually being asked.

### Design mode

Before writing new code, apply
[dependency-rule.md](references/dependency-rule.md),
[solid-and-components.md](references/solid-and-components.md), and
[entities-and-use-cases.md](references/entities-and-use-cases.md) to
decide which layer owns a new responsibility, then
[dotnet-solution-structure.md](references/dotnet-solution-structure.md)
to place it in the right project. When scaffolding a new solution or a
new area of one, also apply
[screaming-architecture.md](references/screaming-architecture.md) to
shape folders around the domain rather than technical roles, and
[testing-strategy.md](references/testing-strategy.md) to set up the test
project layout and architecture test up front rather than bolting it on
later. This complements, and doesn't replace, `test-driven-development`.

### Write mode

While producing code, apply
[interface-adapters.md](references/interface-adapters.md),
[boundaries-and-dtos.md](references/boundaries-and-dtos.md), and
[frameworks-and-details.md](references/frameworks-and-details.md) as
controllers, gateways, and DTOs are written, keeping framework types at
the edge rather than fixing this as an afterthought pass.

### Review mode

When asked to review existing code or a solution structure against
Clean Architecture:

1. Identify which of the nine topics are actually implicated by the code
   under review, and read only those reference files.
2. Evaluate the code against each relevant topic's rules.
3. Report findings using the `ReportFindings` tool: one finding per
   violation, ranked most-severe first. Each finding needs `file`,
   `line`, `summary` (one-sentence statement of the defect), and
   `failure_scenario` (a concrete example of the problem this causes).
   Set `category` to the matching topic slug — `dependency-rule`,
   `solid-and-components`, `entities-and-use-cases`,
   `interface-adapters`, `boundaries-and-dtos`, `frameworks-and-details`,
   `dotnet-solution-structure`, `screaming-architecture`, or
   `testing-strategy`.
4. If the code has no violations, call `ReportFindings` with an empty
   `findings` array rather than skipping the call.

If the `ReportFindings` tool isn't available in the current session, fall
back to emitting the same fields (file, line, summary, failure scenario,
category) as a severity-ranked markdown list, most-severe first — or an
explicit "no violations found" line when the code is clean.

## Output

Design/write mode: code and solution structure that reflect the
relevant principles, applied as part of producing the work — no separate
report. Review mode: a single `ReportFindings` call listing every
violation found (or an empty list if the code is clean) — or, when that
tool isn't available, the same findings as a severity-ranked markdown
list.
