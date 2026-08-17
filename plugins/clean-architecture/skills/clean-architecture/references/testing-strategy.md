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
graph can still slip through). Add an architecture test that asserts
[dependency-rule.md](dependency-rule.md)'s rule directly, and run it in
CI:

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
