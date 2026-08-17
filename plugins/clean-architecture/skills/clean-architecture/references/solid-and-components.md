# SOLID and Component Principles

Applied here at the architecture/assembly level — deciding what belongs
in which .NET project and how projects should depend on each other. For
SOLID applied to individual classes (SRP in particular), see the
`clean-code` skill's `classes.md` if that plugin is installed; this file
doesn't repeat that ground.

## SOLID, at component altitude

- **Single Responsibility** — a component (project/assembly) should have
  one reason to change: one business actor or stakeholder group whose
  requests drive changes to it. `Application.csproj` changing because a
  reporting stakeholder and a billing stakeholder both stuff unrelated
  logic into it is the component-level version of a `Manager` class doing
  too much.
- **Open-Closed** — the architecture should let you add a new use case
  by adding a new project reference or a new file, not by editing
  existing Entities or Use Cases. A new `IOrderRepository` implementation
  should live in its own file in `Infrastructure` and should never
  require changing `IOrderRepository` itself, or the project that
  declares it, or the use case that consumes it.
- **Liskov Substitution** — any implementation of a port
  (`IOrderRepository`, `IPaymentGateway`) must be swappable for another
  without the consuming use case behaving differently — swappable at the
  level of which project gets wired up in DI, not just which class. A
  `FakeOrderRepository` used in tests must honor the same contract a real
  `EfOrderRepository` does — no throwing on operations the real one
  supports, no silently no-op behavior the real one doesn't have.
- **Interface Segregation** — a port interface should expose only what
  its actual consumers need. An `IOrderRepository` with `Save`, `Delete`,
  `GenerateMonthlyReport`, and `SendReceiptEmail` forces every consumer
  and every fake to implement four unrelated concerns; split by actual
  caller need — and if the concerns are unrelated enough, split them into
  separate ports living in separate files or projects, each implemented
  independently, rather than one bloated interface one project must
  satisfy in full.
- **Dependency Inversion** — the mechanism that makes the Dependency Rule
  possible: `Application` defines the interfaces (ports) it needs,
  `Infrastructure` implements them, and the .NET DI container
  (`IServiceCollection`) wires the concrete type to the interface at the
  composition root. The component-level point isn't just "there's an
  interface" — it's that the interface lives in one project
  (`Application`) while every concrete implementation lives in a
  separate, outer project (`Infrastructure`), so `Application.csproj`
  never needs a project reference to `Infrastructure.csproj`. See
  [dependency-rule.md](dependency-rule.md).

## Component cohesion

- **Reuse/Release Equivalence (REP)** — the unit of reuse is the unit of
  release. If `Application` is going to be reused or versioned
  independently (e.g. shared across two Web front ends), it needs its own
  coherent version and changelog, not be an arbitrary slice of a bigger
  release.
- **Common Closure (CCP)** — group classes that change for the same
  reason into the same project. All the classes implementing "place an
  order" (command, handler, validator) belong together, even across
  nominal technical roles, because they change together.
- **Common Reuse (CRP)** — don't force a consumer to take a dependency on
  classes it doesn't use. A `Shared.csproj` holding both `Money` (used
  everywhere) and `LegacyReportFormatter` (used by one obscure feature)
  forces every consumer of `Money` to pull in `LegacyReportFormatter`
  too — split them.

## Component coupling

- **Acyclic Dependencies (ADP)** — the project-reference graph must be a
  DAG. `Infrastructure` → `Application` → `Domain` never cycles back; if
  `Domain` ever needs something from `Application`, that's a sign the
  thing belongs in `Domain` instead, not a reason to add a
  back-reference.
- **Stable Dependencies (SDP)** — depend in the direction of stability.
  `Domain` should be the hardest project to change (few incoming reasons
  to change, many things depend on it) and `Infrastructure`/`Web` the
  easiest to change (framework upgrades, swapped vendors) — never make a
  stable project depend on a volatile one.
- **Stable Abstractions (SAP)** — a stable component should also be
  abstract. `Application`'s stability (few reasons to change) should come
  from being mostly interfaces and orchestration, not concrete
  implementations that accumulate detail over time and make "stable"
  into "stale and hard to extend."
