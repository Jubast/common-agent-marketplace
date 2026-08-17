# clean-architecture

Helps AI agents design, write, and review C#/.NET code and solution
structure following the principles in Robert C. Martin's *Clean
Architecture*, translated into .NET idiom.

## What's in here

- `.claude-plugin/plugin.json` — the plugin manifest, read directly by
  both Claude Code and Copilot CLI.
- `skills/clean-architecture/` — the skill: `SKILL.md` plus nine curated
  topic references under `references/` (the dependency rule, SOLID and
  component principles, entities and use cases, interface adapters,
  boundaries and DTOs, frameworks and details, .NET solution structure,
  screaming architecture, testing strategy).

## Scope

- **C#/.NET only.** Principles are translated into .NET idiom (project
  structure, project-reference direction, idiomatic DI, ASP.NET
  Core/EF Core as the concrete "frameworks and drivers" example), not
  presented generically.
- **Explicit invocation only.** This skill doesn't auto-trigger on
  generic code-writing, code-review, or project-scaffolding requests —
  invoke it by name ("apply the dependency rule", "review this for
  Clean Architecture") or ask about one of its specific topics.
- **Standalone.** Works whether or not the `clean-code` plugin is
  installed; SOLID/component principles are covered here at the
  architecture/assembly level, a different altitude than `clean-code`'s
  class-level SRP coverage.
- **Curated, not exhaustive.** Nine core topics; the book's
  programming-paradigms chapters, its embedded-architecture chapter, and
  its case-study chapters are out of scope. See the design spec for the
  full rationale:
  `docs/superpowers/specs/2026-08-17-clean-architecture-skill-design.md`.

## Using this plugin

Install the marketplace, then this plugin, from a Claude Code session:

```
/plugin marketplace add <org>/<repo>
/plugin install clean-architecture
```

Copilot CLI equivalent:

```
copilot plugin marketplace add <org>/<repo>
copilot plugin install clean-architecture
```

(Replace `<org>/<repo>` with this repository's path once it's pushed to
GitHub.)
