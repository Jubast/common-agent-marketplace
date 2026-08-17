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

These are all instances of "outer types leaking in" — see
[boundaries-and-dtos.md](boundaries-and-dtos.md) for the same leakage
concept described from the boundary-crossing side.

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
