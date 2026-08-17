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
