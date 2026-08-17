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
