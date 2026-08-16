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
