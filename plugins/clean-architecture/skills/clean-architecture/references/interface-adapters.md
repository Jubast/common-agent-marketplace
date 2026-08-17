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
// Humble — thin, untested, no business logic
public class OrdersController : ControllerBase
{
    private readonly IOrderRequestValidator _validator; // testable part

    public OrdersController(IOrderRequestValidator validator) => _validator = validator;

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
