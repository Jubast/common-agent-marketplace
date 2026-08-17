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
    public IReadOnlyList<OrderLine> Lines { get; } = new List<OrderLine>();

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
