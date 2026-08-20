# Error Handling

## Exceptions, not return codes or sentinel values

A method that signals failure by returning `null`, `-1`, or a status
enum forces every caller to remember to check it, right where the
failure happened, mixed into normal control flow. Throwing an exception
separates the error-handling concern from the main logic and can't be
silently ignored the way an unchecked return value can.

```csharp
// Bad
public Order? FindOrder(string id)
{
    if (!_orders.TryGetValue(id, out var order)) return null;
    return order;
}
// caller must remember to null-check every time

// Good
public Order FindOrder(string id)
{
    if (!_orders.TryGetValue(id, out var order))
        throw new OrderNotFoundException(id);
    return order;
}
```

Note the interaction with nullable reference types (below): `string?`
and friends are for values that are *genuinely optional* and that the
caller is expected to check. A failed lookup the caller can't reasonably
proceed past isn't optionality — it's a failure, so throw rather than
handing back a `null` every call site has to defend against.

`TryXxx(out value)` is the one sanctioned exception to "prefer
exceptions" in .NET — it's the established idiom for "this failure is an
expected, common outcome" (`int.TryParse`, `Dictionary.TryGetValue`).
Reach for it when failure is routine, not exceptional; reach for a
thrown exception when it isn't.

## Write the error-handling path first

When a piece of code can fail, write its `try`/`catch` and decide what
the failure means to the caller before filling in the happy path — it's
easier to design the contract around the failure case than to retrofit
it afterward.

## Give exceptions context

A caught exception should tell you what failed and with what — not just
that something, somewhere, went wrong.

```csharp
// Bad
catch (Exception) { throw; }
// or worse — silently swallowed:
catch (Exception) { }

// Good
public class OrderNotFoundException : Exception
{
    public string OrderId { get; }
    public OrderNotFoundException(string orderId)
        : base($"Order '{orderId}' was not found.")
    {
        OrderId = orderId;
    }
}
```

What's wrong with the "Bad" case is the *catch block that adds nothing*
before rethrowing (or that swallows the exception silently) — not the
bare `throw;` itself, which is exactly the right call when you do have
context to add, as below.

When wrapping and rethrowing, preserve the original exception as
`InnerException` and use bare `throw;` (not `throw ex;`) to keep the
original stack trace:

```csharp
catch (SqlException ex)
{
    throw new OrderRepositoryException("Failed to load order.", ex);
}
```

## Define exceptions around the caller's needs

Design an exception type around what the *catching* code needs to do
with it, not around where in the code it originated. If three different
low-level failures all lead the caller to the same recovery action, one
exception type covering all three is better than three types the caller
has to catch identically anyway.

## Don't return null, don't pass null

- Prefer nullable reference types (`string?`) with the compiler's
  nullability warnings enabled, so "this can be absent" is visible in
  the signature instead of discovered at runtime.
- At public boundaries, validate arguments with a guard clause
  (`ArgumentNullException.ThrowIfNull(customer)`) rather than scattering
  defensive null checks through internal code that a validated boundary
  already protects.
- Reach for a project's existing `Option`/`Result`-style type if one is
  already in use — don't introduce a new one solely for this rule.

## Define the normal flow (Special Case objects)

When an absent or exceptional case has one sensible default behavior,
don't push a null check or a branch onto every caller — model the
special case as an object that implements the same interface and
behaves reasonably on its own.

```csharp
public interface ICustomer
{
    decimal LoyaltyDiscount { get; }
}

public class RegisteredCustomer : ICustomer
{
    public decimal LoyaltyDiscount { get; init; }
}

// Special Case: no customer found, but "no discount" is a sensible
// default — callers don't need to know this case exists.
public class GuestCustomer : ICustomer
{
    public decimal LoyaltyDiscount => 0m;
}
```

```csharp
// Bad — every caller must remember the branch
ICustomer? customer = _repository.Find(id);
var discount = customer?.LoyaltyDiscount ?? 0m;

// Good — the special case is baked into the object, not scattered
// across call sites
ICustomer customer = _repository.Find(id) ?? new GuestCustomer();
var discount = customer.LoyaltyDiscount;
```

This is a different tool than nullable reference types, not a
replacement for them: reach for a Special Case object when the absence
has one sensible, reusable default behavior; reach for a nullable type
when absence has no sensible default and the caller genuinely needs to
decide what to do about it.
