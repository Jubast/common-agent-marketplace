# Clean Architecture Skill — Design

Date: 2026-08-17

## Purpose

A new plugin, `clean-architecture`, teaches an agent to design, write, and
review C#/.NET code following the principles in Robert C. Martin's *Clean
Architecture*. It is a pure guidance skill (no executable code) that an
agent explicitly invokes — it does not compete with `superpowers`' broad-
trigger `code-review`, `simplify`, or `test-driven-development` skills for
the same trigger surface, and it stands independently of the `clean-code`
plugin (works whether or not that plugin is installed), even though both
are by the same author and follow the same book-to-skill pattern.

`superpowers` is sourced from an external repo (`obra/superpowers` via a
git URL in `marketplace.json`), so this cannot be added inside it — it
ships as its own local plugin, following the `clean-code` and
`convert-pdf-to-md` pattern.

## Scope decisions

- **Language:** C#/.NET only. Principles are translated into .NET idiom
  (project/assembly organization, project-reference direction, nullable
  reference types, idiomatic DI container usage, ASP.NET Core/EF Core as
  the concrete "frameworks and drivers" example) rather than presented
  generically or left in the book's Java flavor.
- **Trigger:** explicit invocation only — phrases like "clean architecture",
  "apply the dependency rule", "hexagonal architecture", "onion
  architecture", "ports and adapters", "screaming architecture", "is this
  layered correctly", "Uncle Bob's architecture", "review architecture
  boundaries". Not auto-triggered on generic project scaffolding or
  generic "review this code" requests that never invoke the book or its
  vocabulary.
- **Coverage:** curated, not exhaustive. Nine core topics below, drawn from
  the book's Parts III–V (Design Principles, Component Principles,
  Architecture). Part II's programming-paradigm chapters (structured, OO,
  functional programming) are scene-setting rather than actionable and are
  dropped, mirroring how `clean-code` drops its concurrency chapter. The
  embedded-architecture chapter (Part V) is dropped as out of scope for
  typical .NET web/service work. The book's case-study chapters are
  dropped; "The Missing Chapter" (package organization) is folded into
  `screaming-architecture.md` and `dotnet-solution-structure.md` rather
  than kept as a separate file.
- **Relationship to `clean-code`:** standalone. SOLID and component
  cohesion/coupling principles (Parts III–IV) are covered here at the
  architecture/assembly level even though `clean-code` briefly covers SRP
  at the class level in its `classes.md` — different altitude, and this
  skill must be useful on its own without assuming `clean-code` is
  installed.
- **Solution layout:** prescriptive. Because this skill targets .NET
  specifically, it names a concrete default solution/project layout
  (Domain/Application/Infrastructure/Web) with explicit project-reference
  direction, rather than staying purely principle-level. This gives the
  agent something concrete to scaffold toward or evaluate an existing
  solution against.
- **CQRS/MediatR:** noted as a common, optional .NET implementation detail
  for the Use Cases layer, not a requirement — the book doesn't mandate a
  specific pattern for use-case implementation, and this skill shouldn't
  invent a requirement the book doesn't make.

## Plugin layout

```
plugins/clean-architecture/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── clean-architecture/
│       ├── SKILL.md
│       └── references/
│           ├── dependency-rule.md
│           ├── solid-and-components.md
│           ├── entities-and-use-cases.md
│           ├── interface-adapters.md
│           ├── boundaries-and-dtos.md
│           ├── frameworks-and-details.md
│           ├── dotnet-solution-structure.md
│           ├── screaming-architecture.md
│           └── testing-strategy.md
└── README.md
```

`SKILL.md` stays short: frontmatter (`name`, `description` with explicit
trigger phrasing and .NET framing), when to use, how each of the three
modes works, and an index into `references/*.md`. Each reference file is
loaded only when its topic is relevant to the task at hand (progressive
disclosure) — a narrow request like "check the dependency rule in this
file" doesn't pull in all nine topics.

## Content per reference file

| File | Core content, translated to C#/.NET |
|---|---|
| `dependency-rule.md` | The Dependency Rule: source code dependencies point only inward; nothing in an inner circle knows anything about an outer circle. The four circles — Entities, Use Cases, Interface Adapters, Frameworks & Drivers — and what crosses between them. |
| `solid-and-components.md` | SOLID principles and component cohesion (REP, CCP, CRP) / coupling (ADP, SDP, SAP) principles, applied at the assembly/project level — distinct altitude from `clean-code`'s class-level SRP coverage. |
| `entities-and-use-cases.md` | Business rules: Entities (critical business rules + data, framework-independent) vs. Use Cases (application-specific rules that orchestrate entities); request/response models at the use-case boundary; CQRS/MediatR noted as one common, optional .NET implementation choice here. |
| `interface-adapters.md` | Controllers, Presenters, Gateways; converting data between use-case format and external format; the Humble Object pattern for isolating hard-to-test code. |
| `boundaries-and-dtos.md` | Crossing architectural boundaries: dependency inversion at the crossing, DTOs vs. domain entities, avoiding boundary leakage in either direction (inner types leaking out, outer types leaking in). |
| `frameworks-and-details.md` | "The Database is a detail," "The Web is a detail," "Frameworks are details" — ASP.NET Core and EF Core as replaceable plugins at the edge, not the center; keeping framework types out of business rules. |
| `dotnet-solution-structure.md` | Concrete recommended .NET solution layout (see below) and the Main Component/composition root — the one place allowed to know about every layer, wiring concrete Infrastructure implementations to Application's ports via DI. |
| `screaming-architecture.md` | Folder/namespace structure that reflects use cases and domain, not framework or technical layering; incorporates "The Missing Chapter"'s package-organization guidance. |
| `testing-strategy.md` | Tests as the outermost circle — testing business rules independent of UI/DB/frameworks; recommends an architecture test (e.g. NetArchTest) asserting the dependency rule mechanically in CI. |

### Default .NET solution layout (`dotnet-solution-structure.md`)

```
src/
  Domain/         Entities, value objects, domain events/exceptions. No project references out.
  Application/    Use cases (interactors), and ports (interfaces) for anything Infrastructure
                  must provide. References Domain only.
  Infrastructure/ EF Core DbContext, repository implementations, external clients — implements
                  Application's ports. References Application (+ Domain transitively).
  Web/ (or Api/)  Controllers/Presenters (Interface Adapters) + ASP.NET Core host
                  (Frameworks & Drivers). Program.cs is the Main Component / composition root —
                  the one place allowed to reference Infrastructure, wiring concrete
                  implementations to Application's ports via DI.
```

Project references mechanically enforce the Dependency Rule: `Domain` has
zero project references; each subsequent project only references inward.
This is presented as the default recommendation, not a hard requirement —
an agent evaluating an existing solution maps this guidance onto whatever
structure is already there rather than insisting on a rename.

## Skill behavior (three modes)

- **Design mode** — before writing new code: apply `dependency-rule.md`,
  `solid-and-components.md`, and `entities-and-use-cases.md` to decide
  which layer owns a new responsibility, and `dotnet-solution-structure.md`
  to place it in the right project. Complements, does not replace,
  `test-driven-development`.
- **Write mode** — while producing code: apply `interface-adapters.md`,
  `boundaries-and-dtos.md`, and `frameworks-and-details.md` as controllers,
  gateways, and DTOs are written, keeping framework types at the edge.
- **Review mode** — on existing code or a diff: evaluate against the
  curated topics and report findings via the `ReportFindings` tool, same
  tool/shape the `code-review` and `clean-code` skills use (file, line,
  summary, failure scenario, ranked by severity), with `category` set to
  the matching topic slug (e.g. `dependency-rule`, `boundaries-and-dtos`).
  If `ReportFindings` isn't available in the session, fall back to an
  equivalent severity-ranked markdown list, or an explicit "no violations
  found" line when the code is clean.

## Marketplace registration

- `.claude-plugin/marketplace.json` gets a new entry: `name:
  "clean-architecture"`, `description`, `version: "1.0.0"`, `source:
  "./plugins/clean-architecture/"` — same shape as the `clean-code` entry.
- `plugins/clean-architecture/.claude-plugin/plugin.json` — `name`,
  `description`, `version`, `author` (matches the marketplace owner,
  Jubast), `license` (MIT), `keywords` (`clean-architecture`, `dotnet`,
  `csharp`, `software-architecture`, `dependency-rule`).
- `plugins/clean-architecture/README.md` describing the plugin, per
  `CONTRIBUTING.md` and matching `clean-code/README.md`'s structure
  (what's in here, scope, install instructions).

## Testing

- `tests/claude-code/test-clean-architecture.sh` — fast test via `claude
  -p`, mirroring `test-clean-code.sh`'s description-recall pattern
  exactly: ask the live model what `SKILL.md` claims and assert on the
  answers, rather than exercising a real review run. Checks: the
  explicit-invocation trigger conditions (no generic "review this code" or
  generic scaffolding trigger, yes on "review this for clean architecture"
  / "does this follow the dependency rule?"), the target platform, the
  nine curated topics by exact reference-file slug, and review mode's
  reporting tool plus its empty-findings behavior. Registered in
  `run-skill-tests.sh` alongside the `clean-code` and `convert-pdf-to-md`
  tests.
- No integration-tier test — there's no executable script here, just skill
  instructions, so the fast tier is the whole story.

## Explicitly out of scope

- No auto-triggering on generic code tasks or generic .NET project
  scaffolding — explicit invocation only.
- No language other than C#/.NET.
- No Part II programming-paradigm chapters, no embedded-architecture
  chapter, no case-study chapters.
- No mandated use-case implementation pattern (CQRS/MediatR mentioned as
  optional, not required).
- No Copilot CLI-specific handling beyond what `CONTRIBUTING.md` already
  covers (skills are shared as-is between platforms; this plugin has no
  agents, so the Claude-Code-only agent caveat doesn't apply).
