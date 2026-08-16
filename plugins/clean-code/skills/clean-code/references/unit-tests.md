# Unit Tests

## F.I.R.S.T.

- **Fast** — a slow suite doesn't get run often, and a suite that isn't
  run stops catching regressions.
- **Independent** — no test should depend on another test's side effects
  or on running in a particular order.
- **Repeatable** — the same result in any environment; no dependency on
  network access, wall-clock time, or shared external state.
- **Self-validating** — a test reports pass/fail on its own (an
  assertion), never "check the console output by eye."
- **Timely** — written just before or alongside the production code it
  covers, not weeks later once the design has hardened around untested
  assumptions.

## One assert concept per test

A test should verify a single behavior. Multiple `Assert` calls in one
test are fine as long as they're all checking facets of that same
behavior; if a test is checking two unrelated behaviors, split it into
two tests so a failure immediately says which behavior broke.

## Arrange-Act-Assert

Structure each test in three visually distinct sections, with a blank
line between them:

```csharp
[Fact]
public void CalculateTotal_WhenCartIsEmpty_ReturnsZero()
{
    // Arrange
    var cart = new ShoppingCart();

    // Act
    var total = cart.CalculateTotal();

    // Assert
    Assert.Equal(0m, total);
}
```

## Naming

Name the test after the scenario and the expected outcome, not the
method under test alone — `MethodName_WhenScenario_ExpectedBehavior` is
a common, readable convention with both xUnit and NUnit.

## No logic in tests

Keep test methods linear — no loops, conditionals, or branching helper
logic inside the test body. A test with an `if` in it has become code
that itself needs testing, defeating the point.

## Tests are production code

Apply the same standards — clear naming, no duplication, single
responsibility per test — to test code as to the code it tests. A test
suite nobody trusts or wants to touch gets skipped, ignored, or deleted,
which is worse than having no tests at all.
