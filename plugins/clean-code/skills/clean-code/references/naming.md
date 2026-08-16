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
