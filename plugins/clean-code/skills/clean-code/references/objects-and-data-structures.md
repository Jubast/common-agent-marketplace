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
