# Programming Principles

Language-agnostic principles — SOLID, DRY/KISS/YAGNI, Law of Demeter, CQS,
Separation of Concerns, Fail Fast, and composition — expressed in Python.

## Contents

- [SOLID](#solid)
- [DRY · KISS · YAGNI](#dry--kiss--yagni)
- [Law of Demeter](#law-of-demeter)
- [Command–Query Separation](#commandquery-separation)
- [Separation of Concerns](#separation-of-concerns)
- [Fail Fast](#fail-fast)
- [Composition over Inheritance](#composition-over-inheritance)
- [Checklist](#checklist)

## SOLID

| Principle | Rule |
|---|---|
| **S**ingle Responsibility | A module/class has one reason to change. |
| **O**pen/Closed | Open for extension, closed for modification. |
| **L**iskov Substitution | Subtypes are substitutable for their base type. |
| **I**nterface Segregation | Many small protocols beat one fat interface. |
| **D**ependency Inversion | Depend on abstractions (`Protocol`/ABC), not concretions. |

**S — Single Responsibility.** Split generation, rendering, and delivery.

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ReportData:
    rows: tuple[str, ...]


class ReportBuilder:
    def build(self) -> ReportData:
        return ReportData(rows=())


class PdfRenderer:
    def render(self, data: ReportData) -> bytes:
        return "\n".join(data.rows).encode()


class Mailer:
    def send(self, to: str, body: bytes) -> None: ...
```

**O — Open/Closed.** Add behavior by adding a type, not editing a switch.

```python
from __future__ import annotations

from typing import Protocol


class Discount(Protocol):
    def apply(self, price: float) -> float: ...


class VipDiscount:
    def apply(self, price: float) -> float:
        return price * 0.8


class SeasonalDiscount:
    def apply(self, price: float) -> float:
        return price * 0.9


def checkout(price: float, discount: Discount) -> float:
    return discount.apply(price)
```

**L — Liskov Substitution.** Prefer a shared `Protocol` over inheritance that
breaks the parent contract (the classic `Square`/`Rectangle` trap).

```python
from __future__ import annotations

from typing import Protocol


class Shape(Protocol):
    def area(self) -> float: ...


class Rectangle:
    def __init__(self, width: float, height: float) -> None:
        self.width = width
        self.height = height

    def area(self) -> float:
        return self.width * self.height


class Square:
    def __init__(self, side: float) -> None:
        self.side = side

    def area(self) -> float:
        return self.side**2
```

**I — Interface Segregation.** Split fat interfaces; clients depend only on what
they use.

```python
from __future__ import annotations

from typing import Protocol


class Printer(Protocol):
    def print_doc(self) -> None: ...


class Scanner(Protocol):
    def scan(self) -> None: ...


class SimplePrinter:
    def print_doc(self) -> None: ...
```

**D — Dependency Inversion.** High-level code depends on an abstraction; the
implementation is injected (see also `architecture.md`).

```python
from __future__ import annotations

from typing import Protocol


class Database(Protocol):
    def save(self, data: bytes) -> None: ...


class OrderService:
    def __init__(self, db: Database) -> None:
        self._db = db

    def place(self, data: bytes) -> None:
        self._db.save(data)
```

## DRY · KISS · YAGNI

**DRY — Don't Repeat Yourself.** Give each piece of knowledge one authoritative
home. *But* don't deduplicate code that merely looks alike — premature
abstraction is worse than duplication (Rule of Three).

```python
from __future__ import annotations


def assert_valid_email(email: str) -> None:
    if "@" not in email:
        raise ValueError(f"invalid email: {email!r}")


def create_user(email: str) -> None:
    assert_valid_email(email)


def update_user(email: str) -> None:
    assert_valid_email(email)
```

**KISS — Keep It Simple.** Write the simplest thing that solves the problem; code
is read far more often than written.

```python
def is_adult(age: int) -> bool:
    return age >= 18
```

**YAGNI — You Aren't Gonna Need It.** Don't add abstractions or configuration
hooks "just in case"; build them when a real requirement arrives. KISS and YAGNI
together fight accidental complexity.

## Law of Demeter

Talk only to your immediate collaborators — don't reach through chains of objects
you don't own ("train wrecks"). Ask the object for what you need.

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Customer:
    _city: str

    def city_name(self) -> str:  # customer.city_name(), not customer.address.city.name
        return self._city
```

## Command–Query Separation

A method is **either** a query (returns a value, no side effects) **or** a command
(mutates, returns `None`) — never both. See the `separate-query-from-modifier`
entry in `refactoring.md`.

```python
from __future__ import annotations


class Stack:
    def __init__(self) -> None:
        self._items: list[int] = []

    def push(self, item: int) -> None:  # command
        self._items.append(item)

    def peek(self) -> int:  # query
        return self._items[-1]
```

## Separation of Concerns

Keep distinct concerns — interface, domain logic, persistence, I/O — in separate
modules with clear boundaries. Domain logic must not import HTTP or DB packages;
wire those at the edges (`architecture.md`, `data-and-boundaries.md`). A change to
one concern should not ripple into the others.

## Fail Fast

Detect and surface errors as early and loudly as possible: validate at the
boundary, raise immediately on a broken precondition, and never silently swallow
exceptions (`error-handling.md`).

```python
from __future__ import annotations


def parse_age(s: str) -> int:
    try:
        return int(s)
    except ValueError as err:
        raise ValueError(f"invalid age: {s!r}") from err
```

## Composition over Inheritance

Assemble behavior from small, focused collaborators rather than deep inheritance
hierarchies. Use inheritance only for a genuine *is-a* relationship; compose for
*has-a*.

```python
from __future__ import annotations

from typing import Protocol


class Flyer(Protocol):
    def fly(self) -> str: ...


class Swimmer(Protocol):
    def swim(self) -> str: ...


class Duck:  # satisfies both protocols by composition of capabilities
    def fly(self) -> str:
        return "flap"

    def swim(self) -> str:
        return "paddle"
```

## Checklist

- [ ] Each class/function has one reason to change (SRP).
- [ ] New behavior is added by extension (new type/`Protocol` impl), not by editing stable code (OCP).
- [ ] Subtypes honor the base contract; no surprise raises or narrowed inputs (LSP).
- [ ] Interfaces are small and role-specific (ISP); high-level code depends on abstractions (DIP).
- [ ] No copy-pasted knowledge; no premature abstraction either (DRY + Rule of Three).
- [ ] Methods are queries *or* commands, not both (CQS).
- [ ] Domain logic imports no HTTP/DB; concerns are separated.
- [ ] Inputs validated at the boundary; errors raised early, never swallowed (Fail Fast).

## Source

Adapted from [Satcomx00-x00/skills-db](https://github.com/Satcomx00-x00/skills-db)
(`skills/code-quality`, MIT); examples ported to Python. Further reading:
[SOLID](https://en.wikipedia.org/wiki/SOLID),
[The Pragmatic Programmer](https://pragprog.com/titles/tpp20/the-pragmatic-programmer-20th-anniversary-edition/),
[CQS (Fowler)](https://martinfowler.com/bliki/CommandQuerySeparation.html).
