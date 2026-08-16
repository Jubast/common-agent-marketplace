# clean-code

Helps AI agents design, write, and review C#/.NET code following the
principles in Robert C. Martin's *Clean Code*, translated into .NET
idiom.

## What's in here

- `.claude-plugin/plugin.json` — the plugin manifest, read directly by
  both Claude Code and Copilot CLI.
- `skills/clean-code/` — the skill: `SKILL.md` plus ten curated topic
  references under `references/` (naming, functions, comments,
  formatting, error handling, objects and data structures, classes,
  boundaries, unit tests, code smells).

## Scope

- **C#/.NET only.** Principles are translated into .NET idiom (casing
  conventions, exceptions over error codes, nullable reference types,
  idiomatic DI), not presented generically.
- **Explicit invocation only.** This skill doesn't auto-trigger on
  generic code-writing or code-review requests — invoke it by name
  ("apply clean code principles", "review this for clean code") or ask
  about one of its specific topics.
- **Three modes.** Design (shaping structure before code exists), write
  (applying the principles as code is produced), and review (evaluating
  existing code or a diff). Review mode reports findings via the
  `ReportFindings` tool, falling back to a severity-ranked markdown list
  of the same fields when that tool isn't available in the session.
- **Curated, not exhaustive.** Ten core topics; the book's concurrency
  chapter and case-study chapters are out of scope. See this marketplace
  repository's design spec at
  `docs/superpowers/specs/2026-08-16-clean-code-skill-design.md` for the
  full rationale.

## Using this plugin

Install the marketplace, then this plugin, from a Claude Code session:

```
/plugin marketplace add <org>/<repo>
/plugin install clean-code
```

Copilot CLI equivalent:

```
copilot plugin marketplace add <org>/<repo>
copilot plugin install clean-code
```

(Replace `<org>/<repo>` with this repository's path once it's pushed to
GitHub.)
