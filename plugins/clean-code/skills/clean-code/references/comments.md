# Comments

## Comments are a last resort, not a first response

Every comment is an admission that code couldn't say it clearly enough.
Before writing one, try renaming a variable, extracting a method, or
restructuring the condition — most of the time that removes the need
for the comment entirely.

```csharp
// Bad
// check if employee is eligible for full benefits
if ((employee.Flags & EmployeeFlags.Hourly) != 0 && employee.Age > 65)

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
  `// Constructor` above a constructor. Structural markers like
  `// Arrange`/`// Act`/`// Assert` in tests are a sanctioned convention
  rather than ceremony — see [unit-tests.md](unit-tests.md).
- **Closing-brace comments** (`// end for`) — a sign the block is too
  long to read without one; shorten it instead.
