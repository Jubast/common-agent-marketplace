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
