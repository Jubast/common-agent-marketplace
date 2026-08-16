# Classes

## Single Responsibility Principle (SRP)

A class should have one reason to change. If you can't describe what a
class does without using "and" or "or", it's probably doing more than
one job. A vague class name — `Manager`, `Processor`, `Helper`, `Utils`
— with no clear single responsibility is a common symptom, not a
coincidence: the name is vague because the class's job is.

## Cohesion

A class is cohesive when its methods and fields are used together. Low
cohesion — where one subset of methods uses one subset of fields, and
another subset uses a disjoint subset — is a sign the class is really
two classes sharing a file. Splitting along that fault line usually
produces two smaller, more focused classes.

## Organizing for change (Open-Closed)

Isolate a class from a *known, expected* axis of change behind an
abstraction (an interface), so extending behavior means adding a new
implementation rather than editing the existing class. Don't
pre-emptively add an interface for a class with exactly one
implementation and no concrete plan for a second — that's speculative
generality, not open-closed design.

```csharp
// An interface earns its place when a second implementation is real,
// not hypothetical.
public interface IPaymentGateway
{
    Task<PaymentResult> ChargeAsync(decimal amount, string customerId);
}

public class StripePaymentGateway : IPaymentGateway { /* ... */ }
```

## Dependency Inversion

Depend on abstractions, not concrete types — a class should receive its
collaborators (typically via constructor injection) rather than
constructing them itself with `new`. In .NET, register the concrete
implementation against the interface in the DI container
(`IServiceCollection`) and let the runtime wire it up:

```csharp
public class OrderService
{
    private readonly IPaymentGateway _paymentGateway;
    public OrderService(IPaymentGateway paymentGateway) =>
        _paymentGateway = paymentGateway;
}
```

```csharp
services.AddScoped<IPaymentGateway, StripePaymentGateway>();
```

## Small, by responsibility

Measure a class's size by how many responsibilities it holds, not by
line count — but a class that keeps growing because unrelated behavior
keeps landing in it is a candidate for extraction under SRP.
