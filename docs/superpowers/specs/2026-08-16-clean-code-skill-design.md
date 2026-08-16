# Clean Code Skill — Design

Date: 2026-08-16

## Purpose

A new plugin, `clean-code`, teaches an agent to design, write, and review
C#/.NET code following the principles in Robert C. Martin's *Clean Code*.
It is a pure guidance skill (no executable code) that an agent explicitly
invokes — it does not compete with `superpowers`' broad-trigger
`code-review`, `simplify`, or `test-driven-development` skills for the same
trigger surface; it's a distinct lens the agent (or the user) reaches for by
name.

`superpowers` is sourced from an external repo (`obra/superpowers` via a git
URL in `marketplace.json`), so this cannot be added inside it — it ships as
its own local plugin, following the `convert-pdf-to-md` pattern.

## Scope decisions

- **Language:** C#/.NET only. Principles are translated into .NET idiom
  (PascalCase/camelCase conventions, exceptions over error codes, nullable
  reference types, LINQ, records, idiomatic DI container usage) rather than
  presented generically or left in the book's Java flavor.
- **Trigger:** explicit invocation only — phrases like "clean code", "apply
  clean code principles", "clean-code skill", "review for clean code".
  Not auto-triggered on generic write/review activity.
- **Coverage:** curated, not exhaustive. Ten core topics below; the book's
  concurrency chapter (dated Java thread-pattern content) and multi-chapter
  case-study walkthroughs are dropped. Appendix B's ~70 smells are reduced to
  the subset that actually recurs in agent-generated C#.
- **Modes:** one unified skill covering three modes — design, write, review
  — rather than separate skills per phase, since the content overlaps
  heavily and a single entry point is simpler to maintain and invoke.

## Plugin layout

```
plugins/clean-code/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── clean-code/
│       ├── SKILL.md
│       └── references/
│           ├── naming.md
│           ├── functions.md
│           ├── comments.md
│           ├── formatting.md
│           ├── error-handling.md
│           ├── objects-and-data-structures.md
│           ├── classes.md
│           ├── boundaries.md
│           ├── unit-tests.md
│           └── smells.md
└── README.md
```

`SKILL.md` stays short: frontmatter (`name`, `description` with explicit
trigger phrasing and .NET framing), when to use, how each of the three modes
works, and an index into `references/*.md`. Each reference file is loaded
only when its topic is relevant to the task at hand (progressive
disclosure) — a narrow request like "check naming in this file" doesn't pull
in all ten topics.

## Content per reference file

| File | Core content, translated to C#/.NET |
|---|---|
| `naming.md` | Intention-revealing names, no disinformation, pronounceable/searchable names, no encodings — while keeping idiomatic C# casing (PascalCase types/methods, camelCase locals, `_camelCase` private fields), since that's the ecosystem convention, not the "encoding" the book warns against. Nouns for classes, verbs for methods. |
| `functions.md` | Small, one level of abstraction, do one thing, ≤2-3 args (parameter object/record beyond that), no flag arguments, no side effects, command/query separation, prefer exceptions over error codes. |
| `comments.md` | Comments as a failure to self-express in code; good comments (public API `///` XML docs, intent, warnings of consequence) vs. bad (redundant, mandated doc noise, commented-out code, journal comments). |
| `formatting.md` | Vertical/horizontal formatting, newspaper-metaphor file layout, deferring to `.editorconfig`/`dotnet format` rather than restating a style guide. |
| `error-handling.md` | Exceptions over error codes, no returning/passing `null` (nullable reference types as the enforcement tool), custom exceptions carrying context, minimal try/catch bodies. |
| `objects-and-data-structures.md` | Data/object anti-symmetry, Law of Demeter, records/DTOs vs. behavior-rich objects, avoiding hybrids. |
| `classes.md` | SRP, cohesion, small classes, Open-Closed, Dependency Inversion via interfaces + idiomatic .NET DI container usage. |
| `boundaries.md` | Wrapping third-party/NuGet packages, learning tests, adapters at external-API edges. |
| `unit-tests.md` | F.I.R.S.T., one assert-concept per test, AAA pattern, xUnit/NUnit naming conventions. |
| `smells.md` | Curated subset of Appendix B's smells, grouped by category, limited to what recurs in agent-generated C#. |

## Skill behavior (three modes)

- **Design mode** — before writing new code: apply SRP/cohesion/boundaries
  guidance to shape class/module structure. Complements, does not replace,
  `test-driven-development`.
- **Write mode** — while producing code: apply naming/functions/comments/
  formatting/error-handling as code is written.
- **Review mode** — on existing code or a diff: evaluate against the curated
  topics and report findings via the `ReportFindings` tool, same tool/shape
  the `code-review` skill uses (file, line, summary, failure scenario,
  ranked by severity), with `category` set to the matching book topic (e.g.
  `naming`, `functions`, `error-handling`) so results read as a distinct
  lens rather than a duplicate of `code-review`.

## Marketplace registration

- `.claude-plugin/marketplace.json` gets a new entry: `name: "clean-code"`,
  `description`, `version: "1.0.0"`, `source: "./plugins/clean-code/"` — same
  shape as the existing `convert-pdf-to-md` entry.
- `plugins/clean-code/.claude-plugin/plugin.json` — `name`, `description`,
  `version`, `author` (matches the marketplace owner), `license`.
- `plugins/clean-code/README.md` describing the plugin, per
  `CONTRIBUTING.md`.

## Testing

- `tests/claude-code/test-clean-code.sh` — fast test via `claude -p`,
  following `test-convert-pdf-to-md.sh`'s pattern: feed a small,
  deliberately messy C# fixture (bad names, a long multi-purpose method, a
  swallowed exception, magic numbers) and assert that, when the skill is
  explicitly invoked in review mode, it reports findings referencing the
  right principles. Registered in `run-skill-tests.sh` alongside the
  existing PDF test.
- No integration-tier test — there's no executable script here, just skill
  instructions, so the fast tier is the whole story.

## Explicitly out of scope

- No auto-triggering on generic code tasks — explicit invocation only.
- No language other than C#/.NET.
- No concurrency chapter, no book case-study chapters.
- No exhaustive Appendix B smells list — curated subset only.
- No Copilot CLI-specific handling beyond what `CONTRIBUTING.md` already
  covers (skills are shared as-is between platforms; this plugin has no
  agents, so the Claude-Code-only agent caveat doesn't apply).
