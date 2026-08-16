# Clean Code Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `clean-code` plugin to this marketplace — a single, explicit-invocation skill that helps an agent design, write, and review C#/.NET code following a curated, .NET-idiomatic translation of Robert C. Martin's *Clean Code*.

**Architecture:** Static content plugin — `SKILL.md` plus ten `references/*.md` topic files, no executable code. `SKILL.md` stays short (trigger conditions, three usage modes, a topic index) and defers depth to the reference files, which are loaded only when their topic is relevant to the task at hand. Review mode reports findings through the `ReportFindings` tool, the same one `code-review` uses, so clean-code output is a distinct lens rather than a new report format.

**Tech Stack:** Markdown + JSON only. No build step. Verification is `python3 -m json.tool` / frontmatter checks / `grep` for content files, and a real `claude -p` run for the skill-behavior test — matching this repo's existing `convert-pdf-to-md` plugin conventions.

**Spec:** [docs/superpowers/specs/2026-08-16-clean-code-skill-design.md](../specs/2026-08-16-clean-code-skill-design.md)

## Global Constraints

- Owner/author identity everywhere is `name: Jubast`, `email: 30406814+Jubast@users.noreply.github.com` — verbatim in `plugin.json`, matching `marketplace.json`'s existing owner.
- License is MIT.
- Target language/platform is C#/.NET only — no other language is covered or mentioned as a target.
- The skill triggers on **explicit invocation only** (phrases like "clean code", "apply clean code principles", "Uncle Bob") — it must never claim to auto-trigger on generic code-writing or code-review requests, since `superpowers`' `code-review`/`simplify`/`test-driven-development` already own that broad trigger surface.
- Coverage is curated: exactly ten topics (naming, functions, comments, formatting, error handling, objects and data structures, classes, boundaries, unit tests, code smells). The book's concurrency chapter and multi-chapter case-study walkthroughs are explicitly out of scope. `smells.md` is a curated subset of Appendix B, not an exhaustive ~70-item list.
- Review mode reports findings via the `ReportFindings` tool, with `category` set to the matching topic slug, and calls it with an empty `findings` array (not skipped) when no violations are found.
- The plugin lives at `plugins/clean-code/` and is registered in the root `.claude-plugin/marketplace.json` with `source: "./plugins/clean-code/"`, matching the existing `convert-pdf-to-md` entry's shape.
- Test coverage is fast-tier only (`tests/claude-code/test-clean-code.sh`, description-recall style) — no integration tier, since there's no executable script to run end-to-end.

---

### Task 1: Naming and Functions reference files

**Files:**
- Create: `plugins/clean-code/skills/clean-code/references/naming.md`
- Create: `plugins/clean-code/skills/clean-code/references/functions.md`

**Interfaces:**
- Produces: `references/naming.md`, `references/functions.md` — linked from `SKILL.md` (Task 6) and cross-linked from `references/smells.md` (Task 5).

- [ ] **Step 1: Create `plugins/clean-code/skills/clean-code/references/naming.md`**

````markdown
# Naming

Names are the most common thing you write and the primary way you
communicate intent to the next reader (often a future version of
yourself). A good name removes the need for a comment.

## Intention-revealing names

A name should answer: why does this exist, what does it do, how is it
used. If a variable needs a comment to explain it, the name failed.

```csharp
// Bad — needs a comment to be understood
int d; // elapsed time in days

// Good — the name carries the meaning
int elapsedTimeInDays;
```

## Avoid disinformation

Don't call something `accountList` unless it's actually a `List<Account>`
— an `IEnumerable<Account>` or `Account[]` called `accountList` misleads
the reader about what operations are available. Don't use names that
differ in ways that are hard to spot (`ObjectFactory` vs
`ObjectFactoryImpl`, `GetUserData` vs `GetUserInfo` for the same thing).

## Make meaningful distinctions

Don't rename `Account` to `Account2` or `AccountData` just because the
original name was already taken in the same scope — find a name that
actually distinguishes the two concepts, or recognize that one of them
shouldn't exist.

## Pronounceable and searchable names

`genymdhms` is neither. Prefer `generationTimestamp`. Single-letter names
and magic numbers are fine only for the smallest possible scope (a loop
counter `i` inside a three-line loop); anything with a wider scope or a
longer lifetime needs a searchable name.

## Avoid encodings

Don't prefix names with Hungarian-notation type tags (`strName`,
`iCount`). `I`-prefixed interfaces (`IAccount` alongside a concrete
`Account`) are the one encoding that survives this rule in C#/.NET —
it's the ecosystem's standard convention, not the kind of encoding the
rule warns against. Likewise a leading underscore on a private field
(`_customerId`) is idiomatic .NET, not Hungarian notation — it signals
"this is a field" and nothing more, so keep it.

## Class and method names

- Classes and types: nouns or noun phrases — `OrderProcessor`,
  `CustomerRepository`, not `ProcessOrder`.
- Methods: verbs or verb phrases — `CalculateTotal()`, `IsValid()`,
  `TryParse()`. Boolean-returning methods read as a yes/no question:
  `IsEmpty`, `HasExpired`, `CanCancel`.
- One word per concept: pick `Get`, `Fetch`, or `Retrieve` for "read this
  value" and use it consistently — don't mix all three for the same kind
  of operation across different classes.
- Don't be cute: `HolyHandGrenade` instead of `DeleteItems` is a joke
  only the author will find funny later.

## C# casing conventions

| Kind | Convention | Example |
|---|---|---|
| Types, methods, properties, public fields, namespaces, constants | PascalCase | `OrderProcessor`, `CalculateTotal()` |
| Interfaces | `I` + PascalCase | `IOrderRepository` |
| Local variables, parameters | camelCase | `orderId`, `customerName` |
| Private fields | `_` + camelCase | `_orderRepository` |
| Async methods | suffix `Async` | `SaveOrderAsync()` |

## Add meaningful context

If several fields only make sense together (`street`, `city`, `state`),
wrap them in a class (`Address`) instead of prefixing each field name
(`addrStreet`, `addrCity`) to fake the grouping.
````

- [ ] **Step 2: Create `plugins/clean-code/skills/clean-code/references/functions.md`**

````markdown
# Functions

## Small

Functions should be small, then smaller than that. A function that
needs scrolling to read is a function doing too much — extract until
each piece does one identifiable thing.

## Do one thing

A function does one thing if you can't meaningfully extract another
function from it with a name that isn't just a restatement of a step.
If a function's body reads as "and" — validate the order, *and* charge
the card, *and* send the receipt — it's three functions wearing a
trenchcoat.

## One level of abstraction per function

Don't mix high-level policy ("process the order") with low-level detail
("set the 3rd bit of the flags byte") in the same function. Extract the
low-level step into its own well-named function and call it from the
high-level one — this produces the "step-down rule": read top to bottom
like a newspaper, each function followed by the ones it calls at the
next level of detail down.

## Arguments

- 0 arguments is ideal, 1–2 is fine, 3 deserves scrutiny.
- 4 or more: bundle related arguments into a parameter object or
  `record`.

```csharp
// Bad
void CreateOrder(string customerId, string street, string city,
    string state, string zip, decimal amount) { }

// Good
void CreateOrder(string customerId, Address shippingAddress, decimal amount) { }
```

- Avoid boolean flag arguments — a flag means the function does two
  things depending on its value. Split into two named methods instead:

```csharp
// Bad
void Render(bool isSummary) { }

// Good
void RenderSummary() { }
void RenderDetail() { }
```

- Avoid output parameters (`out`/`ref`) in favor of a return value —
  `bool TryParse(string input, out int value)` is a well-established
  .NET idiom and is fine; inventing new `out`-based APIs elsewhere isn't.

## No side effects

A function's name is a promise. `bool IsPasswordValid(string password)`
that also starts a session as a side effect breaks that promise —
callers can't tell from the name, and a caller who only wants the check
gets an unwanted session.

## Command-query separation

A function either does something (a command, returns `void` or a result
describing what happened) or answers something (a query, returns a
value with no observable side effect) — not both. `bool Set(string key,
string value)` that both mutates and reports success is the canonical
violation; prefer `void Set(...)` that throws on failure, or `bool
TrySet(...)` that's honestly named as attempting a mutation.

## Prefer exceptions to error codes

Returning an error code forces the immediate caller to check it right
away, mixed in with normal control flow. Throwing lets error handling
live in one place, and lets intermediate callers ignore what they can't
handle.

```csharp
// Bad
if (DeletePage(page) == Error.None) { ... }

// Good
try { DeletePage(page); ... }
catch (PageDeletionException e) { ... }
```

Extract the body of a `try`/`catch` into its own function so the
function containing the `try` does exactly one thing: handle the error.

## DRY

Duplicated logic means duplicated bugs — a fix applied to one copy and
forgotten in the other. Extract shared logic into a single named
function.
````

- [ ] **Step 3: Verify both files were created with the expected top-level headers**

Run:
```bash
grep -q "^# Naming" plugins/clean-code/skills/clean-code/references/naming.md && \
grep -q "^# Functions" plugins/clean-code/skills/clean-code/references/functions.md && \
echo "OK: naming.md and functions.md created"
```
Expected: `OK: naming.md and functions.md created`

- [ ] **Step 4: Commit**

```bash
git add plugins/clean-code/skills/clean-code/references/naming.md \
        plugins/clean-code/skills/clean-code/references/functions.md
git commit -m "Add clean-code naming and functions reference files"
```

---

### Task 2: Comments and Formatting reference files

**Files:**
- Create: `plugins/clean-code/skills/clean-code/references/comments.md`
- Create: `plugins/clean-code/skills/clean-code/references/formatting.md`

**Interfaces:**
- Produces: `references/comments.md`, `references/formatting.md` — linked from `SKILL.md` (Task 6).

- [ ] **Step 1: Create `plugins/clean-code/skills/clean-code/references/comments.md`**

````markdown
# Comments

## Comments are a last resort, not a first response

Every comment is an admission that code couldn't say it clearly enough.
Before writing one, try renaming a variable, extracting a method, or
restructuring the condition — most of the time that removes the need
for the comment entirely.

```csharp
// Bad
// check if employee is eligible for full benefits
if (employee.Flags & HOURLY_FLAG && employee.Age > 65)

// Good
if (employee.IsEligibleForFullBenefits())
```

## Comments worth writing

- **Legal/license headers**, when your organization requires them.
- **Intent** — why a decision was made, when the "why" isn't derivable
  from the code itself (e.g. why a retry uses this specific backoff).
- **Clarification of an unavoidably obscure algorithm** — a regex, a
  bit-twiddling trick, a workaround for a specific library bug (link the
  bug/issue if one exists).
- **Warning of consequences** — `// not thread-safe; do not share across requests`.
- **`///` XML doc comments on public API surface** — these feed
  IntelliSense and generated docs, so they earn their place even when
  they'd otherwise look redundant with the signature, as long as they add
  real information (parameter constraints, exceptions thrown, nullability
  behavior) rather than restating the method name.
- **`// TODO`**, sparingly, for a genuinely deferred and tracked task —
  not as a permanent home for unfinished work.

## Comments to avoid

- **Restating the code** — `// increment i` above `i++`.
- **Mandated boilerplate `///` comments** that exist only because a
  linter requires every public member to have one, and add nothing
  beyond the method name: `/// <summary>Gets the name.</summary>` on
  `string GetName()`.
- **Commented-out code** — delete it. Git history is the changelog; a
  commented-out block is a mystery for the next reader ("is this needed?
  can I delete it? why is it here?").
- **Journal/changelog comments** at the top of a file (`// 2024-01-03
  jsmith: fixed null check`) — that's what `git log`/`git blame` are for.
- **Noise comments** that add ceremony without information —
  `// Constructor` above a constructor.
- **Closing-brace comments** (`// end for`) — a sign the block is too
  long to read without one; shorten it instead.
````

- [ ] **Step 2: Create `plugins/clean-code/skills/clean-code/references/formatting.md`**

````markdown
# Formatting

Formatting is communication, not decoration — it should make the
structure and relationships in the code visible at a glance.

## File size

Smaller files are easier to hold in your head. A file that's grown
large enough to require heavy scrolling to understand is usually a
signal that it's taking on more than one responsibility (see
[classes.md](classes.md)) — consider whether a split is overdue rather
than reflexively enforcing a line-count limit.

## The newspaper metaphor

Read top to bottom like an article: the highest-level concepts and
public API first, with each level of implementation detail appearing
further down, closer to the functions that need it. A reader should be
able to stop reading after the first few members and already understand
what the class does.

## Vertical spacing

- A blank line between logically distinct concepts (between methods,
  between a field-declaration block and the constructor).
- No blank lines within a tight, closely-related sequence of statements
  — density signals "these belong together."
- Keep related concepts vertically close: declare a local variable near
  its first use, keep instance fields near the top of the class, and
  keep a method near the other methods that call it or that it calls.

## Horizontal formatting

- Prefer lines short enough to read without wrapping in a normal editor
  width; a very long line is often a sign an expression should be broken
  into a well-named local or extracted into its own method.
- Use whitespace to show operator precedence and grouping —
  `a*b + c*d` over `a * b+c * d`.
- Indent consistently to show scope; indentation is the first visual cue
  a reader uses to understand nesting.

## Team conventions over personal preference

Formatting rules belong in the repo's `.editorconfig`, enforced by
`dotnet format`, not in each developer's head. If a formatting rule in
this file conflicts with the repo's `.editorconfig`, the `.editorconfig`
wins — don't hand-format against the team's configured tooling.
````

- [ ] **Step 3: Verify both files were created with the expected top-level headers**

Run:
```bash
grep -q "^# Comments" plugins/clean-code/skills/clean-code/references/comments.md && \
grep -q "^# Formatting" plugins/clean-code/skills/clean-code/references/formatting.md && \
echo "OK: comments.md and formatting.md created"
```
Expected: `OK: comments.md and formatting.md created`

- [ ] **Step 4: Commit**

```bash
git add plugins/clean-code/skills/clean-code/references/comments.md \
        plugins/clean-code/skills/clean-code/references/formatting.md
git commit -m "Add clean-code comments and formatting reference files"
```

---

### Task 3: Error Handling and Objects/Data Structures reference files

**Files:**
- Create: `plugins/clean-code/skills/clean-code/references/error-handling.md`
- Create: `plugins/clean-code/skills/clean-code/references/objects-and-data-structures.md`

**Interfaces:**
- Produces: `references/error-handling.md`, `references/objects-and-data-structures.md` — linked from `SKILL.md` (Task 6) and cross-linked from `references/smells.md` (Task 5).

- [ ] **Step 1: Create `plugins/clean-code/skills/clean-code/references/error-handling.md`**

````markdown
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
````

- [ ] **Step 2: Create `plugins/clean-code/skills/clean-code/references/objects-and-data-structures.md`**

````markdown
# Objects and Data Structures

## Data/object anti-symmetry

- **Objects** hide their data behind behavior and expose operations —
  the caller says *what* it wants done, not *how* the data is laid out.
- **Data structures** (a `record`, a DTO) expose their data and have
  little or no meaningful behavior — the caller operates directly on the
  fields.

These are near-opposites, and mixing them (a class with both public
behavior *and* public mutable state meant for external manipulation) is
usually worse than committing to either pure form.

```csharp
// Object — hides representation, exposes behavior
public class Circle
{
    private readonly double _radius;
    public Circle(double radius) => _radius = radius;
    public double Area() => Math.PI * _radius * _radius;
}

// Data structure — exposes representation, no behavior
public record CircleData(double Radius);
```

## Pick deliberately based on the expected direction of change

Procedural/data-structure style makes it easy to add a new *operation*
over existing types (write one new function) but hard to add a new
*type* (every existing function needs a new case). Object-oriented style
is the reverse: easy to add a new type (implement the interface), harder
to add a new operation (every type needs the new method). Choose based
on which one — new types, or new operations — is more likely to be
added later.

## The Law of Demeter

A method should talk only to its immediate collaborators: its own
fields, its parameters, objects it creates, and objects those return —
not to what those objects contain internally. A chain like this is a
"train wreck" and a Law of Demeter violation:

```csharp
// Bad — reaching through Customer to Address to City
var cityName = order.Customer.Address.City.Name;

// Good — Order exposes what callers actually need
var cityName = order.ShippingCityName;
```

This rule applies to true *objects* hiding behavior — navigating a
chain of plain *data structures* (`order.Customer.Address.City`, where
each is a `record` with no behavior to violate) isn't a Demeter
violation, because there's no encapsulation being bypassed.

## In C#

- Prefer `record`/`record struct` for pure data.
- Prefer a class with private fields and behavior methods for objects; a
  public setter on a behavior-rich class is usually a sign the class is
  being used as a data structure from the outside despite looking like
  an object.
````

- [ ] **Step 3: Verify both files were created with the expected top-level headers**

Run:
```bash
grep -q "^# Error Handling" plugins/clean-code/skills/clean-code/references/error-handling.md && \
grep -q "^# Objects and Data Structures" plugins/clean-code/skills/clean-code/references/objects-and-data-structures.md && \
echo "OK: error-handling.md and objects-and-data-structures.md created"
```
Expected: `OK: error-handling.md and objects-and-data-structures.md created`

- [ ] **Step 4: Commit**

```bash
git add plugins/clean-code/skills/clean-code/references/error-handling.md \
        plugins/clean-code/skills/clean-code/references/objects-and-data-structures.md
git commit -m "Add clean-code error-handling and objects/data-structures reference files"
```

---

### Task 4: Classes and Boundaries reference files

**Files:**
- Create: `plugins/clean-code/skills/clean-code/references/classes.md`
- Create: `plugins/clean-code/skills/clean-code/references/boundaries.md`

**Interfaces:**
- Produces: `references/classes.md`, `references/boundaries.md` — linked from `SKILL.md` (Task 6) and referenced by name from `formatting.md`'s "File size" section (Task 2, already written — that link (`classes.md`) resolves once this task lands).

- [ ] **Step 1: Create `plugins/clean-code/skills/clean-code/references/classes.md`**

````markdown
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
````

- [ ] **Step 2: Create `plugins/clean-code/skills/clean-code/references/boundaries.md`**

````markdown
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
````

- [ ] **Step 3: Verify both files were created with the expected top-level headers**

Run:
```bash
grep -q "^# Classes" plugins/clean-code/skills/clean-code/references/classes.md && \
grep -q "^# Boundaries" plugins/clean-code/skills/clean-code/references/boundaries.md && \
echo "OK: classes.md and boundaries.md created"
```
Expected: `OK: classes.md and boundaries.md created`

- [ ] **Step 4: Commit**

```bash
git add plugins/clean-code/skills/clean-code/references/classes.md \
        plugins/clean-code/skills/clean-code/references/boundaries.md
git commit -m "Add clean-code classes and boundaries reference files"
```

---

### Task 5: Unit Tests and Code Smells reference files

**Files:**
- Create: `plugins/clean-code/skills/clean-code/references/unit-tests.md`
- Create: `plugins/clean-code/skills/clean-code/references/smells.md`

**Interfaces:**
- Consumes: `references/naming.md`, `references/functions.md` (Task 1), `references/error-handling.md`, `references/objects-and-data-structures.md` (Task 3) — `smells.md` links to all four by relative path; they must already exist, which they do after Tasks 1 and 3.
- Produces: `references/unit-tests.md`, `references/smells.md` — linked from `SKILL.md` (Task 6).

- [ ] **Step 1: Create `plugins/clean-code/skills/clean-code/references/unit-tests.md`**

````markdown
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
````

- [ ] **Step 2: Create `plugins/clean-code/skills/clean-code/references/smells.md`**

````markdown
# Code Smells

A curated subset of Robert C. Martin's Appendix B, limited to the smells
that actually recur in day-to-day C#/.NET code. Use this as a review
checklist, not an exhaustive taxonomy.

## Comments

- **Inappropriate or misleading comments** — a comment that no longer
  matches what the code does (code changed, comment didn't).
- **Commented-out code** — delete it; git history already has it.

## Environment

- **Build requires more than one step** — restoring, building, and
  running tests should each be a single command.
- **Tests can't all be run with one command** — if running the full
  suite requires manual steps, it won't get run.

## Functions

- **Too many arguments** — see [functions.md](functions.md).
- **Output arguments (`out`/`ref`) used to return a value** where a
  return value would do (`TryXxx(out value)` for genuinely-expected
  failure is the sanctioned exception — see
  [error-handling.md](error-handling.md)).
- **Flag arguments** — a boolean parameter that switches behavior; split
  into two named methods.
- **Dead function** — a method that's never called. Delete it; version
  control remembers it if it's ever needed again.

## General

- **Duplicated code** — the same logic copy-pasted instead of extracted
  into one place.
- **Code at the wrong level of abstraction** — a low-level detail (a raw
  SQL string, a bit mask) sitting inside a high-level policy method.
- **A base class knowing about its derived classes** — a dependency
  pointing the wrong direction; derived classes should depend on the
  base, never the reverse.
- **Excessive public surface area** — a class exposing more publicly
  than callers actually need, instead of a minimal, intentional
  interface.
- **Dead code** — a branch, method, or field that can never execute or
  is never read.
- **Vertical separation** — a variable declared far from where it's
  used, or a helper method declared far from its only caller.
- **Inconsistent naming for the same concept** — calling the same idea
  `Get`, `Fetch`, and `Retrieve` in different classes.
- **Using a generic `Exception` where a specific exception type already
  exists** in the codebase or the BCL — catching or throwing `Exception`
  broadly hides which failure actually occurred.
- **Public fields on a behavior-rich class** — exposing mutable state
  directly instead of through behavior; see
  [objects-and-data-structures.md](objects-and-data-structures.md).

## Names

- **A name that doesn't describe what the function/variable is for.**
- **A name that doesn't match its level of abstraction** — a low-level
  implementation detail named as if it were a high-level concept, or
  vice versa.
- **Long, descriptive names for tiny, short-lived locals** (and the
  reverse — cryptic single-letter names for anything with real scope).
- **Type/scope encodings** in the name — see [naming.md](naming.md).

## Tests

- **Insufficient tests** — a suite that doesn't cover the cases that
  would actually catch a regression.
- **Coverage percentage treated as the only signal** — 100% line
  coverage with weak assertions catches nothing; coverage tells you what
  ran, not what was actually verified.
- **A skipped or ignored test left unresolved** — a `[Fact(Skip = "...")]`
  is a question about an ambiguity in the code; resolve it (fix the test
  or fix the bug), don't let it sit indefinitely.
````

- [ ] **Step 3: Verify both files were created with the expected top-level headers, and smells.md's cross-links resolve**

Run:
```bash
grep -q "^# Unit Tests" plugins/clean-code/skills/clean-code/references/unit-tests.md && \
grep -q "^# Code Smells" plugins/clean-code/skills/clean-code/references/smells.md && \
test -f plugins/clean-code/skills/clean-code/references/functions.md && \
test -f plugins/clean-code/skills/clean-code/references/error-handling.md && \
test -f plugins/clean-code/skills/clean-code/references/objects-and-data-structures.md && \
test -f plugins/clean-code/skills/clean-code/references/naming.md && \
echo "OK: unit-tests.md and smells.md created, cross-linked files exist"
```
Expected: `OK: unit-tests.md and smells.md created, cross-linked files exist`

- [ ] **Step 4: Commit**

```bash
git add plugins/clean-code/skills/clean-code/references/unit-tests.md \
        plugins/clean-code/skills/clean-code/references/smells.md
git commit -m "Add clean-code unit-tests and smells reference files"
```

---

### Task 6: SKILL.md

**Files:**
- Create: `plugins/clean-code/skills/clean-code/SKILL.md`

**Interfaces:**
- Consumes: all ten reference files from Tasks 1–5 (`naming.md`, `functions.md`, `comments.md`, `formatting.md`, `error-handling.md`, `objects-and-data-structures.md`, `classes.md`, `boundaries.md`, `unit-tests.md`, `smells.md`), plus the `ReportFindings` tool (available in this harness by name — no import needed).
- Produces: the skill entry point, referenced by `plugins/clean-code/README.md` (Task 7) and exercised by `tests/claude-code/test-clean-code.sh` (Task 8).

- [ ] **Step 1: Create `plugins/clean-code/skills/clean-code/SKILL.md`**

````markdown
---
name: clean-code
description: 'Use only when Robert C. Martin''s Clean Code principles are explicitly invoked for C#/.NET code — phrases like "clean code", "apply clean code principles", "clean-code skill", "review this for clean code", "is this SRP-compliant", or "Uncle Bob" — or a direct ask to check naming, functions, comments, formatting, error handling, classes, boundaries, tests, or code smells against the book. Covers design, writing, and review of C#/.NET code against a curated subset of the book (excludes the concurrency chapter and its case-study chapters). Does NOT trigger on generic "review this code" or "write a function that..." requests with no Clean Code framing — this repo''s code-review, simplify, and test-driven-development skills already cover those.'
---

# Clean Code for C#/.NET

## Purpose

Apply the principles from Robert C. Martin's *Clean Code*, translated
into C#/.NET idiom, at three different moments: shaping a design before
code exists, writing code, and reviewing code that already exists. This
skill targets C#/.NET only, and covers a curated subset of the book —
see "What's covered" below.

## When to use this skill

Trigger **only on explicit invocation** — the user (or another skill)
names Clean Code, Uncle Bob, or one of this skill's specific topics
directly: "apply clean code principles here", "review this for clean
code", "is this class SRP-compliant?", "does this method have any code
smells?". Do **not** trigger on a generic "review this code" or "write a
function that..." request that never mentions Clean Code — those are
already covered by this repository's own `code-review`, `simplify`, and
`test-driven-development` skills, and this skill deliberately doesn't
compete with them for that trigger surface.

## What's covered

Ten curated topics, each with its own reference file — read only the
ones relevant to the current task, not all ten every time:

- [naming.md](references/naming.md) — meaningful, pronounceable, unambiguous names
- [functions.md](references/functions.md) — small functions, few arguments, one thing
- [comments.md](references/comments.md) — when a comment is earning its keep
- [formatting.md](references/formatting.md) — vertical/horizontal layout, `.editorconfig`
- [error-handling.md](references/error-handling.md) — exceptions, nulls, exception context
- [objects-and-data-structures.md](references/objects-and-data-structures.md) — objects vs. data, Law of Demeter
- [classes.md](references/classes.md) — SRP, cohesion, dependency inversion
- [boundaries.md](references/boundaries.md) — wrapping third-party code, learning tests
- [unit-tests.md](references/unit-tests.md) — F.I.R.S.T., one concept per test
- [smells.md](references/smells.md) — a curated code-smell checklist

**Not covered:** the book's concurrency chapter (its Java thread-pool
patterns are dated and not directly actionable) and its multi-chapter
case-study walkthroughs. If a task genuinely needs concurrency guidance,
say so explicitly rather than stretching this skill's topics to cover
it.

## How to apply this skill

Three modes — pick based on what's actually being asked.

### Design mode

Before writing new code, apply [classes.md](references/classes.md)
(SRP, cohesion) and [boundaries.md](references/boundaries.md) to shape
the class/module structure — what responsibilities exist, where the
seams and abstractions go. This complements, and doesn't replace,
`test-driven-development`.

### Write mode

While producing code, apply [naming.md](references/naming.md),
[functions.md](references/functions.md),
[comments.md](references/comments.md),
[formatting.md](references/formatting.md), and
[error-handling.md](references/error-handling.md) as the code is
written, not as an afterthought pass.

### Review mode

When asked to review existing code or a diff against Clean Code:

1. Identify which of the ten topics are actually implicated by the code
   under review, and read only those reference files.
2. Evaluate the code against each relevant topic's rules.
3. Report findings using the `ReportFindings` tool: one finding per
   violation, ranked most-severe first. Each finding needs `file`,
   `summary` (one-sentence statement of the defect), and
   `failure_scenario` (a concrete example of the problem this causes).
   Set `category` to the matching topic slug — `naming`, `functions`,
   `comments`, `formatting`, `error-handling`,
   `objects-and-data-structures`, `classes`, `boundaries`,
   `unit-tests`, or `smells`.
4. If the code has no violations, call `ReportFindings` with an empty
   `findings` array rather than skipping the call.

## Output

Design/write mode: code and structure that reflect the relevant
principles, applied as part of producing the work — no separate report.
Review mode: a single `ReportFindings` call listing every violation
found (or an empty list if the code is clean).
````

- [ ] **Step 2: Verify frontmatter, body, and all ten topic links are present**

Run:
```bash
python3 -c "
import re
text = open('plugins/clean-code/skills/clean-code/SKILL.md').read()
m = re.match(r'^---\n(.*?)\n---\n(.*)\$', text, re.DOTALL)
assert m, 'frontmatter block not found'
front, body = m.groups()
assert 'name: clean-code' in front
assert 'description:' in front
assert len(body.strip()) > 0
topics = ['naming', 'functions', 'comments', 'formatting', 'error-handling',
          'objects-and-data-structures', 'classes', 'boundaries',
          'unit-tests', 'smells']
for t in topics:
    assert f'references/{t}.md' in body, f'missing link to {t}.md'
assert 'ReportFindings' in body
print('OK: SKILL.md frontmatter, body, and all ten topic links present')
"
```
Expected: `OK: SKILL.md frontmatter, body, and all ten topic links present`

- [ ] **Step 3: Commit**

```bash
git add plugins/clean-code/skills/clean-code/SKILL.md
git commit -m "Add clean-code SKILL.md"
```

---

### Task 7: Plugin manifest, README, and marketplace registration

**Files:**
- Create: `plugins/clean-code/.claude-plugin/plugin.json`
- Create: `plugins/clean-code/README.md`
- Modify: `.claude-plugin/marketplace.json`

**Interfaces:**
- Consumes: `SKILL.md`'s existence at `plugins/clean-code/skills/clean-code/SKILL.md` (Task 6) — the README describes it; the existing `.claude-plugin/marketplace.json` structure (must preserve the existing `superpowers` and `convert-pdf-to-md` entries).
- Produces: `name: "clean-code"` registered with `source: "./plugins/clean-code/"`, matching `plugin.json`'s `name` field — the same cross-reference contract `convert-pdf-to-md` already satisfies.

- [ ] **Step 1: Create `plugins/clean-code/.claude-plugin/plugin.json`**

```json
{
  "name": "clean-code",
  "description": "Helps AI agents design, write, and review C#/.NET code following the principles in Robert C. Martin's Clean Code, translated into .NET idiom.",
  "version": "1.0.0",
  "author": {
    "name": "Jubast",
    "email": "30406814+Jubast@users.noreply.github.com"
  },
  "license": "MIT",
  "keywords": [
    "clean-code",
    "dotnet",
    "csharp",
    "code-review",
    "software-craftsmanship"
  ]
}
```

- [ ] **Step 2: Create `plugins/clean-code/README.md`**

```markdown
# clean-code

Helps AI agents design, write, and review C#/.NET code following the
principles in Robert C. Martin's *Clean Code*, translated into .NET
idiom.

## What's in here

- `.claude-plugin/plugin.json` — the plugin manifest, read directly by
  both Claude Code and Copilot CLI.
- `skills/clean-code/` — the skill: `SKILL.md` plus ten curated topic
  references under `references/` (naming, functions, comments,
  formatting, error handling, objects and data structures, classes,
  boundaries, unit tests, code smells).

## Scope

- **C#/.NET only.** Principles are translated into .NET idiom (casing
  conventions, exceptions over error codes, nullable reference types,
  idiomatic DI), not presented generically.
- **Explicit invocation only.** This skill doesn't auto-trigger on
  generic code-writing or code-review requests — invoke it by name
  ("apply clean code principles", "review this for clean code") or ask
  about one of its specific topics.
- **Curated, not exhaustive.** Ten core topics; the book's concurrency
  chapter and case-study chapters are out of scope. See the design spec
  for the full rationale:
  `docs/superpowers/specs/2026-08-16-clean-code-skill-design.md`.

## Using this plugin

Install the marketplace, then this plugin, from a Claude Code session:

```
/plugin marketplace add <org>/<repo>
/plugin install clean-code
```

Copilot CLI equivalent:

```
copilot plugin marketplace add <org>/<repo>
copilot plugin install clean-code
```

(Replace `<org>/<repo>` with this repository's path once it's pushed to
GitHub.)
```

- [ ] **Step 3: Add the `clean-code` entry to `.claude-plugin/marketplace.json`**

Add a new object to the end of the existing `plugins` array (after the
`convert-pdf-to-md` entry), keeping the `superpowers` and
`convert-pdf-to-md` entries unchanged:

```json
    {
      "name": "clean-code",
      "description": "Helps AI agents design, write, and review C#/.NET code following the principles in Robert C. Martin's Clean Code, translated into .NET idiom.",
      "version": "1.0.0",
      "source": "./plugins/clean-code/"
    }
```

- [ ] **Step 4: Validate JSON, cross-references, and README links**

Run:
```bash
python3 -m json.tool plugins/clean-code/.claude-plugin/plugin.json > /dev/null && \
python3 -m json.tool .claude-plugin/marketplace.json > /dev/null && \
python3 -c "
import json
mp = json.load(open('.claude-plugin/marketplace.json'))
pl = json.load(open('plugins/clean-code/.claude-plugin/plugin.json'))
entry = next(p for p in mp['plugins'] if p['name'] == pl['name'])
assert entry['source'].rstrip('/') == 'plugins/clean-code', entry['source']
names = [p['name'] for p in mp['plugins']]
assert names == ['superpowers', 'convert-pdf-to-md', 'clean-code'], names
print('OK: marketplace entry matches plugin.json, existing entries preserved')
" && \
test -f plugins/clean-code/skills/clean-code/SKILL.md && \
grep -q 'clean-code' plugins/clean-code/README.md && \
echo "OK: plugin.json, marketplace.json, and README all consistent"
```
Expected: `OK: marketplace entry matches plugin.json, existing entries preserved` followed by `OK: plugin.json, marketplace.json, and README all consistent`

- [ ] **Step 5: Commit**

```bash
git add plugins/clean-code/.claude-plugin/plugin.json \
        plugins/clean-code/README.md \
        .claude-plugin/marketplace.json
git commit -m "Register clean-code plugin: manifest, README, marketplace entry"
```

---

### Task 8: Skill-behavior test

**Files:**
- Create: `tests/claude-code/test-clean-code.sh`
- Modify: `tests/claude-code/run-skill-tests.sh`

**Interfaces:**
- Consumes: `plugins/clean-code/skills/clean-code/SKILL.md` (Task 6) — auto-discovered by `claude -p` when run from the repo root (per `tests/claude-code/README.md`, no marketplace install required for this); `test-helpers.sh`'s `run_claude`/`assert_contains` functions (unchanged, already exist).
- Produces: a fast test registered in `run-skill-tests.sh`'s `tests` array, runnable via `./tests/claude-code/run-skill-tests.sh --test test-clean-code.sh`.

- [ ] **Step 1: Create `tests/claude-code/test-clean-code.sh`**

```bash
#!/usr/bin/env bash
# Test: clean-code skill content and trigger conditions.
# Description-recall style, matching test-convert-pdf-to-md.sh — checks
# what SKILL.md claims, not a real end-to-end review run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: clean-code skill ==="
echo ""

echo "Test 1: Explicit-invocation trigger..."
output=$(run_claude "According to the clean-code skill's description, does it trigger automatically on a generic 'review this code' request that never mentions Clean Code, Uncle Bob, or clean code principles by name? Does it trigger when the user says 'review this for clean code'? Answer using exactly this structure:
Triggers on generic review request: <yes or no>
Triggers on 'review this for clean code': <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Triggers on generic review request:.*no" "Does not trigger on generic review request"
assert_contains "$output" "Triggers on 'review this for clean code':.*yes" "Triggers on explicit clean-code phrasing"
echo ""

echo "Test 2: Target platform and concurrency scope..."
output=$(run_claude "According to the clean-code skill, what language or platform does it target, and does it cover the book's concurrency chapter? Answer using exactly this structure:
Target platform: <answer>
Covers concurrency chapter: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Target platform:.*NET" "Targets C#/.NET"
assert_contains "$output" "Covers concurrency chapter:.*no" "Concurrency chapter out of scope"
echo ""

echo "Test 3: Curated topic coverage..."
output=$(run_claude "According to the clean-code skill, list all of its curated topic areas (the ones with a dedicated reference file). Answer as a comma-separated list." "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "naming" "Lists naming as a topic"
assert_contains "$output" "boundaries" "Lists boundaries as a topic"
assert_contains "$output" "smells" "Lists code smells as a topic"
echo ""

echo "Test 4: Review-mode reporting..."
output=$(run_claude "According to the clean-code skill, in review mode, what tool does it use to report findings, and what does it do if the reviewed code has no violations at all? Answer using exactly this structure:
Reporting tool: <tool name>
No violations found: <what it does>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Reporting tool:.*ReportFindings" "Uses ReportFindings tool"
assert_contains "$output" "No violations found:.*empty" "Calls ReportFindings with an empty list when clean"
echo ""

echo "=== All clean-code skill tests passed ==="
```

- [ ] **Step 2: Make the test executable**

```bash
chmod +x tests/claude-code/test-clean-code.sh
```

- [ ] **Step 3: Register the test in `run-skill-tests.sh`**

In `tests/claude-code/run-skill-tests.sh`, change the `tests` array:

```bash
tests=(
    "test-convert-pdf-to-md.sh"
)
```

to:

```bash
tests=(
    "test-convert-pdf-to-md.sh"
    "test-clean-code.sh"
)
```

And update the `--help` text's `Tests:` listing:

```
            echo "Tests:"
            echo "  test-convert-pdf-to-md.sh  Skill content and requirements"
```

to:

```
            echo "Tests:"
            echo "  test-convert-pdf-to-md.sh  Skill content and requirements"
            echo "  test-clean-code.sh         Skill content and trigger conditions"
```

- [ ] **Step 4: Run the new test from the repo root**

Run:
```bash
./tests/claude-code/run-skill-tests.sh --test test-clean-code.sh --verbose
```
Expected: all four `[PASS]` lines and `STATUS: PASSED`. If any assertion fails, re-read the failing prompt's output (printed on failure by `assert_contains`) and fix the corresponding wording in `SKILL.md` (Task 6) — don't loosen the test to match wrong behavior.

- [ ] **Step 5: Run the full fast suite to confirm no regression**

Run:
```bash
./tests/claude-code/run-skill-tests.sh
```
Expected: `STATUS: PASSED`, both `test-convert-pdf-to-md.sh` and `test-clean-code.sh` passing.

- [ ] **Step 6: Commit**

```bash
git add tests/claude-code/test-clean-code.sh tests/claude-code/run-skill-tests.sh
git commit -m "Add clean-code skill-behavior test"
```

---

## Definition of Done

- `plugins/clean-code/` contains: `.claude-plugin/plugin.json`, `README.md`, `skills/clean-code/SKILL.md`, and ten files under `skills/clean-code/references/` (`naming.md`, `functions.md`, `comments.md`, `formatting.md`, `error-handling.md`, `objects-and-data-structures.md`, `classes.md`, `boundaries.md`, `unit-tests.md`, `smells.md`).
- `.claude-plugin/marketplace.json` lists exactly three plugins, in order: `superpowers`, `convert-pdf-to-md`, `clean-code`.
- `tests/claude-code/test-clean-code.sh` exists, is executable, and is registered in `run-skill-tests.sh`'s `tests` array and `--help` text.
- `./tests/claude-code/run-skill-tests.sh` (run from the repo root, no `--integration`) reports `STATUS: PASSED`.
- `git log --oneline` shows one commit per task (8 new commits on top of the spec commit already on `main`).
