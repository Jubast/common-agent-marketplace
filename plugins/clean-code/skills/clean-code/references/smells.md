# Code Smells

A curated subset of Robert C. Martin's Appendix B, limited to the smells
that actually recur in day-to-day C#/.NET code. Use this as a review
checklist, not an exhaustive taxonomy.

## Comments

- **Inappropriate or misleading comments** — a comment that no longer
  matches what the code does (code changed, comment didn't). See
  [comments.md](comments.md).
- **Commented-out code** — delete it; git history already has it.
- **A comment compensating for unclear code** — a comment explaining a
  condition or block that a rename or an extracted method would have made
  self-evident; see [comments.md](comments.md).

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
- **Magic numbers and magic strings** — an unexplained literal sitting
  inline (`if (order.Total > 500)`, `Thread.Sleep(86400000)`, a repeated
  `"pending"` status string) where a named constant, an enum member, or a
  `TimeSpan.FromDays(1)` would say what it actually means. See
  [naming.md](naming.md) for the casing convention on the constant you
  extract.
- **A class with more than one reason to change** — unrelated
  responsibilities bundled into one type, so a change to either drags the
  other along; see [classes.md](classes.md).
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
  would actually catch a regression. See [unit-tests.md](unit-tests.md).
- **Coverage percentage treated as the only signal** — 100% line
  coverage with weak assertions catches nothing; coverage tells you what
  ran, not what was actually verified.
- **A skipped or ignored test left unresolved** — a `[Fact(Skip = "...")]`
  is a question about an ambiguity in the code; resolve it (fix the test
  or fix the bug), don't let it sit indefinitely.
- **Slow, order-dependent, or non-self-validating tests** — any breach of
  F.I.R.S.T., or logic (loops, conditionals) inside a test body; see
  [unit-tests.md](unit-tests.md).
