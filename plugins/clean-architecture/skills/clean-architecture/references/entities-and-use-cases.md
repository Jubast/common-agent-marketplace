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
    public Guid Id { get; } = Guid.NewGuid();
    public Guid CustomerId { get; }
    private readonly List<OrderLine> _lines = new();
    public IReadOnlyList<OrderLine> Lines => _lines;

    public Order(Guid customerId)
    {
        CustomerId = customerId;
    }

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
        var order = new Order(request.CustomerId);
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
