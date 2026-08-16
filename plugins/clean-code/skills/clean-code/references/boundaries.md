# Boundaries

## Wrap third-party code

Don't let a NuGet package's API shape spread throughout the codebase.
Define a small interface expressed in your own domain's vocabulary, and
implement it with a thin adapter over the third-party client. This keeps
one place responsible for adapting to the vendor's API, and makes it
possible to swap the dependency later without touching every call site.

```csharp
// Your domain's interface
public interface IEmailSender
{
    Task SendAsync(string to, string subject, string body);
}

// Thin adapter over the actual vendor SDK
public class SendGridEmailSender : IEmailSender
{
    private readonly SendGridClient _client;
    public SendGridEmailSender(SendGridClient client) => _client = client;

    public Task SendAsync(string to, string subject, string body) =>
        _client.SendEmailAsync(/* map to SendGrid's own types here */);
}
```

## Learning tests

Before wiring a new NuGet package into production code, write small
tests that exercise its public API directly — not to test the vendor's
code, but to learn how it actually behaves, and to catch breaking
changes automatically the next time the package is upgraded. These tests
live alongside the codebase's other tests and run in CI like any other
test.

## Adapters at every external boundary

The same wrapping principle applies to any external system, not just
library packages — an HTTP API, a database/ORM, a message queue. Define
the boundary interface in terms your domain understands, and keep the
vendor-specific detail (connection strings, wire formats, client
libraries) entirely inside the adapter that implements it.

## Coding against a boundary that doesn't exist yet

When a dependency (an external team's API, a not-yet-built service)
isn't available yet, define the interface you wish existed and code
against that, with a fake/stub implementation for now — replace it with
the real adapter once the dependency exists, without touching the
calling code.
