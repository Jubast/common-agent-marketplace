# Clean Architecture Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `clean-architecture` plugin to this marketplace — a single, explicit-invocation skill that helps an agent design, write, and review C#/.NET code and solution structure following a curated, .NET-idiomatic translation of Robert C. Martin's *Clean Architecture*.

**Architecture:** Static content plugin — `SKILL.md` plus nine `references/*.md` topic files, no executable code. `SKILL.md` stays short (trigger conditions, three usage modes, a topic index) and defers depth to the reference files, which are loaded only when their topic is relevant to the task at hand. Review mode reports findings through the `ReportFindings` tool, the same one `code-review` and `clean-code` use, so output is a distinct lens rather than a new report format. The plugin is standalone — it works whether or not the `clean-code` plugin is installed.

**Tech Stack:** Markdown + JSON only. No build step. Verification is `python3 -m json.tool` / frontmatter checks / `grep` for content files, and a real `claude -p` run for the skill-behavior test — matching this repo's existing `clean-code` and `convert-pdf-to-md` plugin conventions.

**Spec:** [docs/superpowers/specs/2026-08-17-clean-architecture-skill-design.md](../specs/2026-08-17-clean-architecture-skill-design.md)

## Global Constraints

- Owner/author identity everywhere is `name: Jubast`, `email: 30406814+Jubast@users.noreply.github.com` — verbatim in `plugin.json`, matching `marketplace.json`'s existing owner.
- License is MIT.
- Target language/platform is C#/.NET only — no other language is covered or mentioned as a target.
- The skill triggers on **explicit invocation only** (phrases like "clean architecture", "apply the dependency rule", "hexagonal architecture", "onion architecture", "ports and adapters", "screaming architecture", "Uncle Bob's architecture") — it must never claim to auto-trigger on generic code-writing, generic code-review, or generic new-.NET-project-scaffolding requests.
- Coverage is curated: exactly nine topics (dependency rule, SOLID and components, entities and use cases, interface adapters, boundaries and DTOs, frameworks and details, .NET solution structure, screaming architecture, testing strategy). The book's programming-paradigms chapters, its embedded-architecture chapter, and its case-study chapters are explicitly out of scope.
- `solid-and-components.md` covers SOLID/component cohesion/coupling at the assembly/project level — it does not repeat `clean-code`'s class-level SRP coverage, and this plugin must be useful standalone without `clean-code` installed.
- `dotnet-solution-structure.md` prescribes a concrete default layout (`Domain`/`Application`/`Infrastructure`/`Web` projects with inward-only project references) — presented as a default to scaffold toward or evaluate against, not a hard requirement that overrides an existing repo's structure.
- CQRS/MediatR is mentioned only as a common, optional .NET implementation choice for the Use Cases layer — never as a requirement.
- Review mode reports findings via the `ReportFindings` tool, with `category` set to the matching topic slug, and calls it with an empty `findings` array (not skipped) when no violations are found.
- The plugin lives at `plugins/clean-architecture/` and is registered in the root `.claude-plugin/marketplace.json` with `source: "./plugins/clean-architecture/"`, and in the root `README.md`'s "Available plugins" list, matching the existing `clean-code` entry's shape in both places.
- Test coverage is fast-tier only (`tests/claude-code/test-clean-architecture.sh`, description-recall style) — no integration tier, since there's no executable script to run end-to-end.

---

### Task 1: Dependency Rule and SOLID/Components reference files

**Files:**
- Create: `plugins/clean-architecture/skills/clean-architecture/references/dependency-rule.md`
- Create: `plugins/clean-architecture/skills/clean-architecture/references/solid-and-components.md`

**Interfaces:**
- Produces: `references/dependency-rule.md`, `references/solid-and-components.md` — linked from `SKILL.md` (Task 6) and cross-linked from each other and from later reference files (Tasks 2–5).

- [ ] **Step 1: Create `plugins/clean-architecture/skills/clean-architecture/references/dependency-rule.md`**

````markdown
# The Dependency Rule

## The rule itself

Source code dependencies must point only inward, toward higher-level
policy. Nothing in an inner circle may know anything at all about
something in an outer circle — not its name, not the package/project it
lives in, not that it exists.

Four circles, from innermost to outermost:

1. **Entities** — enterprise-wide critical business rules and data.
2. **Use Cases** — application-specific business rules that orchestrate entities.
3. **Interface Adapters** — controllers, presenters, gateways that convert data between use cases and the outside world.
4. **Frameworks & Drivers** — the web framework, the database, the UI, any external tool.

## What "inward" means in a .NET solution

Project references are the mechanical enforcement of the rule: a
`Domain.csproj` (Entities) has zero `<ProjectReference>` elements.
`Application.csproj` (Use Cases) references only `Domain`.
`Infrastructure.csproj` and `Web.csproj` (Interface Adapters + Frameworks
& Drivers) reference `Application` — never the other way around. See
[dotnet-solution-structure.md](dotnet-solution-structure.md) for the full
layout.

```csharp
// Domain/Order.cs — Entities circle. No `using` pointing outward.
public class Order
{
    public Guid Id { get; }
    public IReadOnlyList<OrderLine> Lines { get; }

    public decimal Total() => Lines.Sum(l => l.Quantity * l.UnitPrice);
}
```

```csharp
// BAD — Domain/Order.cs referencing an outer-circle package.
using Microsoft.EntityFrameworkCore; // Infrastructure detail leaking into Entities

[Table("Orders")] // EF Core attribute — Domain shouldn't know EF Core exists
public class Order { /* ... */ }
```

## When control flow wants to go the wrong way

A Use Case (inner) needs to persist an `Order` — an operation whose
natural implementation (EF Core, SQL) lives in an outer circle. Resolve
this with Dependency Inversion, not by letting the dependency point
outward: the inner circle declares the interface it needs, and an outer
circle implements it.

```csharp
// Application/IOrderRepository.cs — the port, owned by the inner circle
public interface IOrderRepository
{
    Task SaveAsync(Order order);
}

// Infrastructure/EfOrderRepository.cs — the adapter, in the outer circle
public class EfOrderRepository : IOrderRepository
{
    private readonly AppDbContext _db;
    public EfOrderRepository(AppDbContext db) => _db = db;

    public async Task SaveAsync(Order order)
    {
        _db.Orders.Add(order);
        await _db.SaveChangesAsync();
    }
}
```

Source dependencies still point inward — `Infrastructure` references
`Application`'s interface — even though the runtime *call* flows from
Application out to Infrastructure. This is the mechanism the rest of the
skill's topics rely on; see
[solid-and-components.md](solid-and-components.md) for the Dependency
Inversion Principle this pattern is built on.

## What crosses a boundary

Only simple data (a DTO, a `record`) crosses between circles — never an
outer-circle type passed inward, and never an inner-circle Entity handed
outward for an outer layer to manipulate directly. See
[boundaries-and-dtos.md](boundaries-and-dtos.md).
````

- [ ] **Step 2: Create `plugins/clean-architecture/skills/clean-architecture/references/solid-and-components.md`**

````markdown
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
  by adding new classes, not by editing existing Entities or Use Cases.
  A new `IOrderRepository` implementation should never require changing
  `IOrderRepository` itself or the use case that consumes it.
- **Liskov Substitution** — any implementation of a port
  (`IOrderRepository`, `IPaymentGateway`) must be swappable for another
  without the consuming use case behaving differently. A
  `FakeOrderRepository` used in tests must honor the same contract a real
  `EfOrderRepository` does — no throwing on operations the real one
  supports, no silently no-op behavior the real one doesn't have.
- **Interface Segregation** — a port interface should expose only what
  its actual consumers need. An `IOrderRepository` with `Save`, `Delete`,
  `GenerateMonthlyReport`, and `SendReceiptEmail` forces every consumer
  and every fake to implement four unrelated concerns; split by actual
  caller need.
- **Dependency Inversion** — the mechanism that makes the Dependency Rule
  possible: Application defines the interfaces (ports) it needs,
  Infrastructure implements them, and the .NET DI container
  (`IServiceCollection`) wires the concrete type to the interface at the
  composition root. See [dependency-rule.md](dependency-rule.md).

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
  DAG. `Domain` → `Application` → `Infrastructure` never cycles back; if
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
````

- [ ] **Step 3: Verify both files were created with the expected top-level headers**

Run:
```bash
grep -q "^# The Dependency Rule" plugins/clean-architecture/skills/clean-architecture/references/dependency-rule.md && \
grep -q "^# SOLID and Component Principles" plugins/clean-architecture/skills/clean-architecture/references/solid-and-components.md && \
echo "OK: dependency-rule.md and solid-and-components.md created"
```
Expected: `OK: dependency-rule.md and solid-and-components.md created`

- [ ] **Step 4: Commit**

```bash
git add plugins/clean-architecture/skills/clean-architecture/references/dependency-rule.md \
        plugins/clean-architecture/skills/clean-architecture/references/solid-and-components.md
git commit -m "Add clean-architecture dependency-rule and solid-and-components reference files"
```

---

### Task 2: Entities/Use Cases and Interface Adapters reference files

**Files:**
- Create: `plugins/clean-architecture/skills/clean-architecture/references/entities-and-use-cases.md`
- Create: `plugins/clean-architecture/skills/clean-architecture/references/interface-adapters.md`

**Interfaces:**
- Consumes: `references/dependency-rule.md` (Task 1) — both files link to it.
- Produces: `references/entities-and-use-cases.md`, `references/interface-adapters.md` — linked from `SKILL.md` (Task 6) and cross-linked from `references/dotnet-solution-structure.md` (Task 4).

- [ ] **Step 1: Create `plugins/clean-architecture/skills/clean-architecture/references/entities-and-use-cases.md`**

````markdown
# Entities and Use Cases

## Entities: enterprise-wide business rules

An Entity encapsulates the business rules and data that would exist even
if this specific application didn't — the rules a company would state
the same way regardless of whether the system was a web app, a batch
job, or a phone call to a clerk. In .NET, Entities live in the `Domain`
project with zero outward dependencies: no EF Core attributes, no
ASP.NET types, no JSON-serialization attributes chosen for one
particular API's convenience.

```csharp
// Domain/Order.cs
public class Order
{
    private readonly List<OrderLine> _lines = new();
    public IReadOnlyList<OrderLine> Lines => _lines;

    public void AddLine(Product product, int quantity)
    {
        if (quantity <= 0)
            throw new InvalidOrderException("Quantity must be positive.");
        _lines.Add(new OrderLine(product, quantity));
    }

    public decimal Total() => _lines.Sum(l => l.Quantity * l.UnitPrice);
}
```

## Use Cases: application-specific business rules

A Use Case describes how the application uses Entities to achieve a
specific goal a user or external system asked for — "place an order,"
"cancel a subscription." It orchestrates Entities and ports; it does not
duplicate the business rules Entities already own.

```csharp
// Application/Orders/PlaceOrder.cs
public record PlaceOrderRequest(Guid CustomerId, IReadOnlyList<OrderLineRequest> Lines);
public record PlaceOrderResponse(Guid OrderId, decimal Total);

public class PlaceOrderUseCase
{
    private readonly IOrderRepository _orders;
    private readonly IProductCatalog _catalog;

    public PlaceOrderUseCase(IOrderRepository orders, IProductCatalog catalog)
    {
        _orders = orders;
        _catalog = catalog;
    }

    public async Task<PlaceOrderResponse> ExecuteAsync(PlaceOrderRequest request)
    {
        var order = new Order();
        foreach (var line in request.Lines)
        {
            var product = await _catalog.FindAsync(line.ProductId);
            order.AddLine(product, line.Quantity); // business rule lives on Order, not here
        }

        await _orders.SaveAsync(order);
        return new PlaceOrderResponse(order.Id, order.Total());
    }
}
```

## Request/response models, not Entities, at the use-case boundary

`PlaceOrderRequest`/`PlaceOrderResponse` are use-case-specific shapes,
not the `Order` entity itself. Returning `Order` directly would leak the
Entity's full shape (and any future change to it) to every caller across
the boundary, including outer circles that should only see what this
specific use case promises to return.

## Ports belong to the use case, not to Infrastructure

`IOrderRepository` and `IProductCatalog` are declared in `Application`
because the use case defines what it needs — Infrastructure's job is
only to satisfy that contract. See
[dependency-rule.md](dependency-rule.md) for why the interface lives on
the inward side.

## CQRS/MediatR

Splitting use cases into commands (write) and queries (read), each with
a MediatR `IRequestHandler`, is a common and idiomatic way to implement
this layer in .NET — but it's an implementation choice, not something
the book requires. A plain use-case class like `PlaceOrderUseCase` above
satisfies the same architecture; don't introduce MediatR into a codebase
solely because "Clean Architecture" was mentioned.
````

- [ ] **Step 2: Create `plugins/clean-architecture/skills/clean-architecture/references/interface-adapters.md`**

````markdown
# Interface Adapters

This layer converts data between the shape Use Cases want and the shape
the outside world (HTTP, a database, a UI) wants. Nothing here contains
business rules — it's translation only.

## Controllers

A controller's only job is to translate an inbound request into a
use-case request model, invoke the use case, and hand the result to a
Presenter. It should contain no business logic — if a controller method
has an `if` that decides something about *the business*, not about
*HTTP concerns* (status codes, model binding), that logic belongs in the
use case instead.

```csharp
// Web/Controllers/OrdersController.cs
[ApiController]
[Route("orders")]
public class OrdersController : ControllerBase
{
    private readonly PlaceOrderUseCase _placeOrder;

    public OrdersController(PlaceOrderUseCase placeOrder) => _placeOrder = placeOrder;

    [HttpPost]
    public async Task<IActionResult> Post(PlaceOrderApiRequest request)
    {
        var result = await _placeOrder.ExecuteAsync(request.ToUseCaseRequest());
        return Ok(OrderPresenter.ToApiResponse(result));
    }
}
```

## Presenters

A Presenter shapes a use case's output model into whatever the specific
delivery mechanism needs — an API response DTO, a Razor view model. This
keeps view-specific formatting (date formats, field renaming for a
particular client, pagination envelopes) out of the Use Cases layer,
which shouldn't know or care how its result will be displayed.

```csharp
public static class OrderPresenter
{
    public static PlaceOrderApiResponse ToApiResponse(PlaceOrderResponse result) =>
        new(result.OrderId, result.Total.ToString("C"));
}
```

## Gateways

A Gateway is an Interface Adapter implementing a port the Use Cases layer
declared (`IOrderRepository`) against a specific outer-circle technology.
In a typical .NET Clean Architecture solution, Gateways and the
Frameworks & Drivers code implementing them (EF Core, `HttpClient`)
pragmatically share one `Infrastructure` project rather than being split
into two more projects — see
[dotnet-solution-structure.md](dotnet-solution-structure.md). The
important boundary is still enforced: `Infrastructure` implements
`Application`'s interfaces, never the reverse.

## Humble Object

When a piece of code is genuinely hard to unit test — because it's
tightly bound to a framework, the UI, or the database — split it into
two: a **humble** part with no logic (just delegates to the framework)
and left untested, and a testable part holding all the actual logic.

```csharp
// Humble — thin, untested, no branching logic
public class OrderApiController : ControllerBase
{
    private readonly IOrderRequestValidator _validator; // testable part
    [HttpPost]
    public IActionResult Post(PlaceOrderApiRequest request) =>
        _validator.Validate(request) is { IsValid: true }
            ? Ok()
            : BadRequest();
}

// Testable — pure logic, no ASP.NET Core dependency
public class OrderRequestValidator : IOrderRequestValidator
{
    public ValidationResult Validate(PlaceOrderApiRequest request) { /* ... */ }
}
```
````

- [ ] **Step 3: Verify both files were created with the expected top-level headers**

Run:
```bash
grep -q "^# Entities and Use Cases" plugins/clean-architecture/skills/clean-architecture/references/entities-and-use-cases.md && \
grep -q "^# Interface Adapters" plugins/clean-architecture/skills/clean-architecture/references/interface-adapters.md && \
echo "OK: entities-and-use-cases.md and interface-adapters.md created"
```
Expected: `OK: entities-and-use-cases.md and interface-adapters.md created`

- [ ] **Step 4: Commit**

```bash
git add plugins/clean-architecture/skills/clean-architecture/references/entities-and-use-cases.md \
        plugins/clean-architecture/skills/clean-architecture/references/interface-adapters.md
git commit -m "Add clean-architecture entities-and-use-cases and interface-adapters reference files"
```

---

### Task 3: Boundaries/DTOs and Frameworks/Details reference files

**Files:**
- Create: `plugins/clean-architecture/skills/clean-architecture/references/boundaries-and-dtos.md`
- Create: `plugins/clean-architecture/skills/clean-architecture/references/frameworks-and-details.md`

**Interfaces:**
- Consumes: `references/dependency-rule.md` (Task 1) — `boundaries-and-dtos.md` links to it.
- Produces: `references/boundaries-and-dtos.md`, `references/frameworks-and-details.md` — linked from `SKILL.md` (Task 6).

- [ ] **Step 1: Create `plugins/clean-architecture/skills/clean-architecture/references/boundaries-and-dtos.md`**

````markdown
# Boundaries and DTOs

## What's allowed to cross

Only simple data crosses an architectural boundary: a `record`, a DTO, a
primitive. Passing an Entity itself across a boundary hands outer-circle
code a live reference to inner-circle behavior it shouldn't invoke
directly, and couples the boundary's shape to the Entity's internal
structure.

```csharp
// BAD — Use Case returns the Entity itself
public Task<Order> ExecuteAsync(PlaceOrderRequest request) { ... }
// Now the controller (Interface Adapters) can call order.AddLine(...)
// directly, bypassing the use case that's supposed to own that flow.

// GOOD — Use Case returns a response shaped for this specific operation
public Task<PlaceOrderResponse> ExecuteAsync(PlaceOrderRequest request) { ... }
```

## Dependency inversion at the crossing

When the natural direction of a call would point outward (an inner
circle needing something an outer circle provides), invert it: the inner
circle declares an interface, the outer circle implements it. This is
the same mechanism as [dependency-rule.md](dependency-rule.md)'s
`IOrderRepository` example — it's what makes "data crosses inward *and*
outward while source dependencies still only point inward" possible.

## Leakage in both directions

- **Outer types leaking in** — a Domain or Application class referencing
  `Microsoft.AspNetCore.Http.HttpContext`, an EF Core `DbSet<T>`, or a
  vendor SDK type directly. The fix is always a port interface owned by
  the inner circle.
- **Inner types leaking out without translation** — a controller handing
  a raw `Order` entity to `System.Text.Json` and serializing it directly
  as the API response. Even though this is technically "crossing
  outward," skipping the Presenter/DTO step still couples the API's
  public contract to the Entity's internal shape — a Domain refactor now
  breaks API consumers.

## DTOs vs. Entities

A DTO (or `record` request/response model) has no behavior and exists
only to carry data across one specific boundary — it's allowed to be
reshaped freely per boundary (an API DTO, a persistence DTO, a message-
queue payload can all differ) precisely because it isn't the Entity.
Don't reuse one DTO type across multiple unrelated boundaries just to
avoid writing a second `record` — that reintroduces the coupling DTOs
exist to prevent.
````

- [ ] **Step 2: Create `plugins/clean-architecture/skills/clean-architecture/references/frameworks-and-details.md`**

````markdown
# Frameworks and Details

## The database is a detail

The choice of SQL Server vs. PostgreSQL, EF Core vs. Dapper, is a
decision that should be deferrable and swappable without touching
`Domain` or `Application`. If swapping the ORM requires editing a Use
Case, the boundary has already been violated.

Markers of this violation in a .NET codebase:

- `[Table]`, `[Column]`, `[Key]`, or other EF Core data-annotation
  attributes on a `Domain` class.
- A `DbContext` (or `DbSet<T>`) referenced from `Application` or
  `Domain` instead of only from `Infrastructure`.
- Entity classes whose shape is driven by what EF Core's change tracker
  needs (public parameterless constructors solely for materialization,
  every property with a public setter) rather than by what the business
  rule needs.

## The web is a detail

ASP.NET Core, Minimal APIs vs. MVC controllers, gRPC — the delivery
mechanism is a plugin at the edge, not the center of the design.
`Domain` and `Application` should have zero package reference to
`Microsoft.AspNetCore.*`. A Use Case should never take an `HttpContext`,
read a query string, or return an `IActionResult`.

## Frameworks are details, not the architecture

Don't let a framework's base classes shape core design decisions — e.g.
inheriting `Order` from an EF Core-provided base class, or designing Use
Cases around a specific web framework's request pipeline. Use the
framework as a replaceable plugin: depend on it from the outer circles
only, and keep it swappable in principle even if never actually swapped.

## Why this matters beyond theory

A framework or ORM upgrade, or a decision to add a second delivery
mechanism (a background worker calling the same use cases a web API
calls), should only ever touch `Infrastructure`/`Web` — never ripple into
`Domain`/`Application`. If it does, that's the concrete cost of a
details-are-details violation, not an abstract rule for its own sake.
````

- [ ] **Step 3: Verify both files were created with the expected top-level headers**

Run:
```bash
grep -q "^# Boundaries and DTOs" plugins/clean-architecture/skills/clean-architecture/references/boundaries-and-dtos.md && \
grep -q "^# Frameworks and Details" plugins/clean-architecture/skills/clean-architecture/references/frameworks-and-details.md && \
echo "OK: boundaries-and-dtos.md and frameworks-and-details.md created"
```
Expected: `OK: boundaries-and-dtos.md and frameworks-and-details.md created`

- [ ] **Step 4: Commit**

```bash
git add plugins/clean-architecture/skills/clean-architecture/references/boundaries-and-dtos.md \
        plugins/clean-architecture/skills/clean-architecture/references/frameworks-and-details.md
git commit -m "Add clean-architecture boundaries-and-dtos and frameworks-and-details reference files"
```

---

### Task 4: .NET Solution Structure and Screaming Architecture reference files

**Files:**
- Create: `plugins/clean-architecture/skills/clean-architecture/references/dotnet-solution-structure.md`
- Create: `plugins/clean-architecture/skills/clean-architecture/references/screaming-architecture.md`

**Interfaces:**
- Consumes: `references/interface-adapters.md` (Task 2) — `dotnet-solution-structure.md` is linked from it; `references/solid-and-components.md` (Task 1) — `screaming-architecture.md` links to it.
- Produces: `references/dotnet-solution-structure.md`, `references/screaming-architecture.md` — linked from `SKILL.md` (Task 6) and cross-linked from earlier files (Tasks 1–3, already written — those links resolve once this task lands).

- [ ] **Step 1: Create `plugins/clean-architecture/skills/clean-architecture/references/dotnet-solution-structure.md`**

````markdown
# .NET Solution Structure

## Default layout

```
src/
  Domain/         Entities, value objects, domain events/exceptions.
                  Zero project references.
  Application/    Use cases and ports (interfaces) for anything
                  Infrastructure must provide. References Domain only.
  Infrastructure/ EF Core DbContext, repository implementations, external
                  clients — implements Application's ports.
                  References Application (and Domain transitively).
  Web/            Controllers/Presenters (Interface Adapters) + the
                  ASP.NET Core host (Frameworks & Drivers).
                  References Application and Infrastructure.
```

This is a default, not a hard requirement — when evaluating an existing
solution, map this guidance onto whatever structure is already there
rather than insisting on a rename. When scaffolding a new solution with
no existing structure to respect, use this layout.

## Project references enforce the Dependency Rule mechanically

```xml
<!-- Domain/Domain.csproj — no ProjectReference elements at all -->

<!-- Application/Application.csproj -->
<ItemGroup>
  <ProjectReference Include="..\Domain\Domain.csproj" />
</ItemGroup>

<!-- Infrastructure/Infrastructure.csproj -->
<ItemGroup>
  <ProjectReference Include="..\Application\Application.csproj" />
</ItemGroup>

<!-- Web/Web.csproj -->
<ItemGroup>
  <ProjectReference Include="..\Application\Application.csproj" />
  <ProjectReference Include="..\Infrastructure\Infrastructure.csproj" />
</ItemGroup>
```

Because `Domain` has no outward references, the compiler itself rejects
any accidental `using` that would violate the rule — a `Domain` class
can't reference an `Infrastructure` type even by mistake, because
`Domain.csproj` never sees that assembly.

## The Main Component / composition root

`Web`'s `Program.cs` is the one place in the solution allowed to know
about every layer — it's where concrete `Infrastructure` implementations
get wired to `Application`'s ports via the DI container. No other file
should perform this wiring.

```csharp
// Web/Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDbContext<AppDbContext>(opts =>
    opts.UseSqlServer(builder.Configuration.GetConnectionString("Default")));

builder.Services.AddScoped<IOrderRepository, EfOrderRepository>();
builder.Services.AddScoped<IProductCatalog, EfProductCatalog>();
builder.Services.AddScoped<PlaceOrderUseCase>();

var app = builder.Build();
app.MapControllers();
app.Run();
```

Everything below `Program.cs` — every Use Case, every Controller — only
ever sees the interfaces (`IOrderRepository`), never `EfOrderRepository`
directly.
````

- [ ] **Step 2: Create `plugins/clean-architecture/skills/clean-architecture/references/screaming-architecture.md`**

````markdown
# Screaming Architecture

## The folder structure should scream the domain, not the framework

Looking at the top level of `Application`, a reader should be able to
tell this is an order-management system — not that it's "an ASP.NET Core
app" or "a system with Services and Repositories." Framework and
technical-layer names belong to the projects that are actually
frameworks and drivers (`Web`, `Infrastructure`), not to `Domain` or
`Application`.

## Organize Application by feature, not by technical role

```
# BAD — organized by technical role; nothing here says what the app does
Application/
  Services/
    OrderService.cs
    CustomerService.cs
  Handlers/
    PlaceOrderHandler.cs
    CancelOrderHandler.cs
  Validators/
    OrderValidator.cs

# GOOD — organized by use case/feature; the folder names are the business
Application/
  Orders/
    PlaceOrder.cs        (request, response, use case together)
    CancelOrder.cs
    OrderValidator.cs
  Customers/
    RegisterCustomer.cs
```

Grouping by feature keeps everything that changes together (the request
model, response model, use case, and its validator for one operation)
physically together — this is the Common Closure Principle from
[solid-and-components.md](solid-and-components.md) applied at the folder
level, not just the project level.

## Layer at the solution level, feature at the folder level

The two organizing schemes aren't in conflict: `Domain` / `Application` /
`Infrastructure` / `Web` as separate projects is what enforces the
Dependency Rule (see
[dotnet-solution-structure.md](dotnet-solution-structure.md)); organizing
*within* `Application` by feature is what makes the solution scream its
purpose once you're inside that boundary.

## Framework-shaped folders are expected — in the right project

`Web/Controllers/`, `Web/Middleware/`, `Infrastructure/Migrations/` are
fine — `Web` and `Infrastructure` genuinely are the Frameworks & Drivers
circle, so framework-shaped folder names there are accurate, not a
smell. The smell is `Domain/Controllers/` or `Application/DbContexts/` —
technical, framework-flavored folder names appearing in a circle that's
supposed to be framework-independent.
````

- [ ] **Step 3: Verify both files were created with the expected top-level headers**

Run:
```bash
grep -q "^# .NET Solution Structure" plugins/clean-architecture/skills/clean-architecture/references/dotnet-solution-structure.md && \
grep -q "^# Screaming Architecture" plugins/clean-architecture/skills/clean-architecture/references/screaming-architecture.md && \
echo "OK: dotnet-solution-structure.md and screaming-architecture.md created"
```
Expected: `OK: dotnet-solution-structure.md and screaming-architecture.md created`

- [ ] **Step 4: Commit**

```bash
git add plugins/clean-architecture/skills/clean-architecture/references/dotnet-solution-structure.md \
        plugins/clean-architecture/skills/clean-architecture/references/screaming-architecture.md
git commit -m "Add clean-architecture dotnet-solution-structure and screaming-architecture reference files"
```

---

### Task 5: Testing Strategy reference file

**Files:**
- Create: `plugins/clean-architecture/skills/clean-architecture/references/testing-strategy.md`

**Interfaces:**
- Consumes: none of this plan's earlier files by link (this file stands alone conceptually, tying the Dependency Rule to CI enforcement).
- Produces: `references/testing-strategy.md` — linked from `SKILL.md` (Task 6), completing the nine-topic set.

- [ ] **Step 1: Create `plugins/clean-architecture/skills/clean-architecture/references/testing-strategy.md`**

````markdown
# Testing Strategy

## Tests are the outermost circle

Tests depend on every other circle (they exercise Domain, Application,
Infrastructure, and Web) but nothing depends on tests — the Dependency
Rule still applies to the test suite's own project references.

## Test business rules without a framework in the loop

Unit-test `Domain` and `Application` directly, in isolation from ASP.NET
Core and the real database — supply fakes/mocks for the ports
`Application` declares (`IOrderRepository`), not a real
`EfOrderRepository` backed by a live connection.

```csharp
public class PlaceOrderUseCaseTests
{
    [Fact]
    public async Task ExecuteAsync_SavesOrderWithCorrectTotal()
    {
        var repo = new FakeOrderRepository();
        var catalog = new FakeProductCatalog(new Product("sku-1", 10m));
        var useCase = new PlaceOrderUseCase(repo, catalog);

        var response = await useCase.ExecuteAsync(
            new PlaceOrderRequest(CustomerId: Guid.NewGuid(),
                Lines: new[] { new OrderLineRequest("sku-1", Quantity: 3) }));

        Assert.Equal(30m, response.Total);
    }
}
```

No `WebApplicationFactory`, no real `DbContext`, no HTTP call — this
test runs in milliseconds and fails only when the business rule it
targets actually breaks.

## Mirror the source project structure

`Domain.Tests`, `Application.Tests`, `Infrastructure.Tests` (integration
tests against a real or containerized database), and thin `Web`-level
tests keep the test suite's own dependency direction sane, and make it
obvious at a glance which layer a failing test is about.

## Enforce the Dependency Rule with an architecture test

Don't rely on project references alone to catch every violation (a
`using` that compiles fine within an already-too-permissive reference
graph can still slip through). Add an architecture test that asserts the
rule directly, and run it in CI:

```csharp
[Fact]
public void Domain_Should_Not_Depend_On_Outer_Layers()
{
    var result = Types.InAssembly(typeof(Order).Assembly)
        .Should()
        .NotHaveDependencyOnAny("Application", "Infrastructure", "Microsoft.AspNetCore", "Microsoft.EntityFrameworkCore")
        .GetResult();

    Assert.True(result.IsSuccessful, string.Join(", ", result.FailingTypeNames ?? Array.Empty<string>()));
}
```

(Using `NetArchTest.Rules` — any similar architecture-testing library
works the same way.) This turns the Dependency Rule from an aspiration
enforced only by code review into something a broken PR fails on
automatically.
````

- [ ] **Step 2: Verify the file was created with the expected top-level header**

Run:
```bash
grep -q "^# Testing Strategy" plugins/clean-architecture/skills/clean-architecture/references/testing-strategy.md && \
echo "OK: testing-strategy.md created"
```
Expected: `OK: testing-strategy.md created`

- [ ] **Step 3: Commit**

```bash
git add plugins/clean-architecture/skills/clean-architecture/references/testing-strategy.md
git commit -m "Add clean-architecture testing-strategy reference file"
```

---

### Task 6: SKILL.md

**Files:**
- Create: `plugins/clean-architecture/skills/clean-architecture/SKILL.md`

**Interfaces:**
- Consumes: all nine reference files from Tasks 1–5 (`dependency-rule.md`, `solid-and-components.md`, `entities-and-use-cases.md`, `interface-adapters.md`, `boundaries-and-dtos.md`, `frameworks-and-details.md`, `dotnet-solution-structure.md`, `screaming-architecture.md`, `testing-strategy.md`), plus the `ReportFindings` tool (available in this harness by name — no import needed).
- Produces: the skill entry point, referenced by `plugins/clean-architecture/README.md` (Task 7) and exercised by `tests/claude-code/test-clean-architecture.sh` (Task 8).

- [ ] **Step 1: Create `plugins/clean-architecture/skills/clean-architecture/SKILL.md`**

````markdown
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
to place it in the right project. This complements, and doesn't replace,
`test-driven-development`.

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
````

- [ ] **Step 2: Verify frontmatter, body, and all nine topic links are present**

Run:
```bash
python3 -c "
import re
text = open('plugins/clean-architecture/skills/clean-architecture/SKILL.md').read()
m = re.match(r'^---\n(.*?)\n---\n(.*)\$', text, re.DOTALL)
assert m, 'frontmatter block not found'
front, body = m.groups()
assert 'name: clean-architecture' in front
assert 'description:' in front
assert len(body.strip()) > 0
topics = ['dependency-rule', 'solid-and-components', 'entities-and-use-cases',
          'interface-adapters', 'boundaries-and-dtos', 'frameworks-and-details',
          'dotnet-solution-structure', 'screaming-architecture', 'testing-strategy']
for t in topics:
    assert f'references/{t}.md' in body, f'missing link to {t}.md'
assert 'ReportFindings' in body
print('OK: SKILL.md frontmatter, body, and all nine topic links present')
"
```
Expected: `OK: SKILL.md frontmatter, body, and all nine topic links present`

- [ ] **Step 3: Commit**

```bash
git add plugins/clean-architecture/skills/clean-architecture/SKILL.md
git commit -m "Add clean-architecture SKILL.md"
```

---

### Task 7: Plugin manifest, READMEs, and marketplace registration

**Files:**
- Create: `plugins/clean-architecture/.claude-plugin/plugin.json`
- Create: `plugins/clean-architecture/README.md`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`

**Interfaces:**
- Consumes: `SKILL.md`'s existence at `plugins/clean-architecture/skills/clean-architecture/SKILL.md` (Task 6) — the README describes it; the existing `.claude-plugin/marketplace.json` and root `README.md` structures (must preserve the existing `superpowers`, `convert-pdf-to-md`, and `clean-code` entries).
- Produces: `name: "clean-architecture"` registered with `source: "./plugins/clean-architecture/"`, matching `plugin.json`'s `name` field — the same cross-reference contract `clean-code` already satisfies.

- [ ] **Step 1: Create `plugins/clean-architecture/.claude-plugin/plugin.json`**

```json
{
  "name": "clean-architecture",
  "description": "Helps AI agents design, write, and review C#/.NET code and solution structure following the principles in Robert C. Martin's Clean Architecture, translated into .NET idiom.",
  "version": "1.0.0",
  "author": {
    "name": "Jubast",
    "email": "30406814+Jubast@users.noreply.github.com"
  },
  "license": "MIT",
  "keywords": [
    "clean-architecture",
    "dotnet",
    "csharp",
    "software-architecture",
    "dependency-rule"
  ]
}
```

- [ ] **Step 2: Create `plugins/clean-architecture/README.md`**

```markdown
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
```

- [ ] **Step 3: Add the `clean-architecture` entry to `.claude-plugin/marketplace.json`**

Add a new object to the end of the existing `plugins` array (after the
`clean-code` entry), keeping the `superpowers`, `convert-pdf-to-md`, and
`clean-code` entries unchanged:

```json
    {
      "name": "clean-architecture",
      "description": "Helps AI agents design, write, and review C#/.NET code and solution structure following the principles in Robert C. Martin's Clean Architecture, translated into .NET idiom.",
      "version": "1.0.0",
      "source": "./plugins/clean-architecture/"
    }
```

- [ ] **Step 4: Add the `clean-architecture` entry to the root `README.md`'s "Available plugins" list**

In the root `README.md`, after the existing `clean-code` bullet under
`## Available plugins`, add:

```markdown
- [`clean-architecture`](plugins/clean-architecture/) — helps AI agents
  design, write, and review C#/.NET code and solution structure
  following the principles in Robert C. Martin's Clean Architecture,
  translated into .NET idiom.
```

- [ ] **Step 5: Validate JSON, cross-references, and README links**

Run:
```bash
python3 -m json.tool plugins/clean-architecture/.claude-plugin/plugin.json > /dev/null && \
python3 -m json.tool .claude-plugin/marketplace.json > /dev/null && \
python3 -c "
import json
mp = json.load(open('.claude-plugin/marketplace.json'))
pl = json.load(open('plugins/clean-architecture/.claude-plugin/plugin.json'))
entry = next(p for p in mp['plugins'] if p['name'] == pl['name'])
assert entry['source'].rstrip('/') == 'plugins/clean-architecture', entry['source']
names = [p['name'] for p in mp['plugins']]
assert names == ['superpowers', 'convert-pdf-to-md', 'clean-code', 'clean-architecture'], names
print('OK: marketplace entry matches plugin.json, existing entries preserved')
" && \
test -f plugins/clean-architecture/skills/clean-architecture/SKILL.md && \
grep -q 'clean-architecture' plugins/clean-architecture/README.md && \
grep -q 'clean-architecture' README.md && \
echo "OK: plugin.json, marketplace.json, and both READMEs consistent"
```
Expected: `OK: marketplace entry matches plugin.json, existing entries preserved` followed by `OK: plugin.json, marketplace.json, and both READMEs consistent`

- [ ] **Step 6: Commit**

```bash
git add plugins/clean-architecture/.claude-plugin/plugin.json \
        plugins/clean-architecture/README.md \
        .claude-plugin/marketplace.json \
        README.md
git commit -m "Register clean-architecture plugin: manifest, READMEs, marketplace entry"
```

---

### Task 8: Skill-behavior test

**Files:**
- Create: `tests/claude-code/test-clean-architecture.sh`
- Modify: `tests/claude-code/run-skill-tests.sh`

**Interfaces:**
- Consumes: `plugins/clean-architecture/skills/clean-architecture/SKILL.md` (Task 6) — auto-discovered by `claude -p` when run from the repo root (per `tests/claude-code/README.md`, no marketplace install required for this); `test-helpers.sh`'s `run_claude`/`assert_contains` functions (unchanged, already exist).
- Produces: a fast test registered in `run-skill-tests.sh`'s `tests` array, runnable via `./tests/claude-code/run-skill-tests.sh --test test-clean-architecture.sh`.

- [ ] **Step 1: Create `tests/claude-code/test-clean-architecture.sh`**

```bash
#!/usr/bin/env bash
# Test: clean-architecture skill content and trigger conditions.
# Description-recall style, matching test-clean-code.sh — checks what
# SKILL.md claims, not a real end-to-end review run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: clean-architecture skill ==="
echo ""

echo "Test 1: Explicit-invocation trigger..."
output=$(run_claude "According to the clean-architecture skill's description, does it trigger automatically on a generic 'review this code' request that never mentions Clean Architecture, the dependency rule, or Uncle Bob by name? Does it trigger when the user says 'does this follow the dependency rule?'? Answer using exactly this structure:
Triggers on generic review request: <yes or no>
Triggers on 'does this follow the dependency rule?': <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Triggers on generic review request:.*no" "Does not trigger on generic review request"
assert_contains "$output" "Triggers on 'does this follow the dependency rule?':.*yes" "Triggers on explicit dependency-rule phrasing"
echo ""

echo "Test 2: Target platform and programming-paradigms scope..."
output=$(run_claude "According to the clean-architecture skill, what language or platform does it target, and does it cover the book's programming-paradigms chapters (structured, object-oriented, functional programming)? Answer using exactly this structure:
Target platform: <answer>
Covers programming-paradigms chapters: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Target platform:.*NET" "Targets C#/.NET"
assert_contains "$output" "Covers programming-paradigms chapters:.*no" "Programming-paradigms chapters out of scope"
echo ""

echo "Test 3: Curated topic coverage..."
output=$(run_claude "According to the clean-architecture skill, list all of its curated topic areas (the ones with a dedicated reference file). Name each one by its exact reference file base name — the \`references/<slug>.md\` slug, without the \`.md\` extension. Answer as a comma-separated list." "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "dependency-rule" "Lists dependency-rule as a topic"
assert_contains "$output" "screaming-architecture" "Lists screaming-architecture as a topic"
# This skill's exact hyphenated slug — a model answering from general Clean
# Architecture knowledge, without SKILL.md loaded, is unlikely to produce it verbatim.
assert_contains "$output" "boundaries-and-dtos" "Lists boundaries-and-dtos by its exact slug"
echo ""

echo "Test 4: Review-mode reporting..."
output=$(run_claude "According to the clean-architecture skill, in review mode, what tool does it use to report findings, and what does it do if the reviewed code has no violations at all? Answer using exactly this structure:
Reporting tool: <tool name>
No violations found: <what it does>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Reporting tool:.*ReportFindings" "Uses ReportFindings tool"
assert_contains "$output" "No violations found:.*empty" "Calls ReportFindings with an empty list when clean"
echo ""

echo "=== All clean-architecture skill tests passed ==="
```

- [ ] **Step 2: Make the test executable**

```bash
chmod +x tests/claude-code/test-clean-architecture.sh
```

- [ ] **Step 3: Register the test in `run-skill-tests.sh`**

In `tests/claude-code/run-skill-tests.sh`, change the `tests` array:

```bash
tests=(
    "test-convert-pdf-to-md.sh"
    "test-clean-code.sh"
)
```

to:

```bash
tests=(
    "test-convert-pdf-to-md.sh"
    "test-clean-code.sh"
    "test-clean-architecture.sh"
)
```

And update the `--help` text's `Tests:` listing:

```
            echo "Tests:"
            echo "  test-convert-pdf-to-md.sh  Skill content and requirements"
            echo "  test-clean-code.sh         Skill content and trigger conditions"
```

to:

```
            echo "Tests:"
            echo "  test-convert-pdf-to-md.sh    Skill content and requirements"
            echo "  test-clean-code.sh           Skill content and trigger conditions"
            echo "  test-clean-architecture.sh   Skill content and trigger conditions"
```

- [ ] **Step 4: Run the new test from the repo root**

Run:
```bash
./tests/claude-code/run-skill-tests.sh --test test-clean-architecture.sh --verbose
```
Expected: all four `[PASS]` lines and `STATUS: PASSED`. If any assertion fails, re-read the failing prompt's output (printed on failure by `assert_contains`) and fix the corresponding wording in `SKILL.md` (Task 6) — don't loosen the test to match wrong behavior.

- [ ] **Step 5: Run the full fast suite to confirm no regression**

Run:
```bash
./tests/claude-code/run-skill-tests.sh
```
Expected: `STATUS: PASSED`, with `test-convert-pdf-to-md.sh`, `test-clean-code.sh`, and `test-clean-architecture.sh` all passing.

- [ ] **Step 6: Commit**

```bash
git add tests/claude-code/test-clean-architecture.sh tests/claude-code/run-skill-tests.sh
git commit -m "Add clean-architecture skill-behavior test"
```

---

## Definition of Done

- `plugins/clean-architecture/` contains: `.claude-plugin/plugin.json`, `README.md`, `skills/clean-architecture/SKILL.md`, and nine files under `skills/clean-architecture/references/` (`dependency-rule.md`, `solid-and-components.md`, `entities-and-use-cases.md`, `interface-adapters.md`, `boundaries-and-dtos.md`, `frameworks-and-details.md`, `dotnet-solution-structure.md`, `screaming-architecture.md`, `testing-strategy.md`).
- `.claude-plugin/marketplace.json` lists exactly four plugins, in order: `superpowers`, `convert-pdf-to-md`, `clean-code`, `clean-architecture`.
- Root `README.md`'s "Available plugins" list includes `clean-architecture`.
- `tests/claude-code/test-clean-architecture.sh` exists, is executable, and is registered in `run-skill-tests.sh`'s `tests` array and `--help` text.
- `./tests/claude-code/run-skill-tests.sh` (run from the repo root, no `--integration`) reports `STATUS: PASSED`.
- `git log --oneline` shows one commit per task (8 new commits on top of the spec commit already on `main`).
