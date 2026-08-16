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
