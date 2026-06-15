# Refactoring

A catalog of small, behavior-preserving transformations that improve the internal structure of Python code without changing what it does.

## Contents

- Catalog — the full set at a glance: what each move does and when to reach for it.
- Refactorings — one section each, with a Before/After Python pair and a caution where it matters.
- Principles — the discipline that keeps refactoring safe and cheap.
- Source — attribution and further reading.

## Catalog

| Refactoring | What it does | When |
|---|---|---|
| Extract Method | Pulls a fragment into a named function | A block needs a comment, repeats, or a function runs long |
| Inline Method | Replaces a trivial call with its body | The body is as clear as its name; needless indirection |
| Extract Variable | Names a complex expression | An expression is dense, repeated, or a domain concept |
| Replace Temp with Query | Turns a read-only temp into a method | The temp is assigned once and the value is reusable |
| Replace Magic Number | Names a bare literal as a constant | A literal carries domain meaning or recurs |
| Decompose Conditional | Names the condition and each branch | An `if`/`else` hides multi-line business rules |
| Guard Clauses | Returns early on edge cases | Deep nesting buries the happy path |
| Replace Conditional with Polymorphism | Moves each type-case into a subclass | A type-switch drives behavior in several places |
| Extract Class | Splits an overloaded class in two | A class has more than one reason to change |
| Move Method | Relocates a method to the data it uses | A method leans on another class more than its own |
| Introduce Parameter Object | Groups a recurring parameter cluster | The same arguments always travel together |
| Separate Query from Modifier | Splits a value-returning method from its side effect | One method both returns a value and mutates state |

## Refactorings

### Extract Method

Group a fragment into its own function named for its intent. **When:** a block needs a comment to explain *what* it does, repeats elsewhere, or a function has outgrown a single screen.

**Before**

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Item:
    name: str
    qty: int
    price: int


@dataclass(frozen=True)
class Order:
    id: int
    items: list[Item]


def print_order(order: Order) -> None:
    print(f"Order #{order.id}")
    total = 0
    for item in order.items:
        print(f"  {item.name} x{item.qty} = {item.price * item.qty}")
        total += item.price * item.qty
    print(f"Total: {total}")
```

**After**

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Item:
    name: str
    qty: int
    price: int


@dataclass(frozen=True)
class Order:
    id: int
    items: list[Item]


def print_order(order: Order) -> None:
    print(f"Order #{order.id}")
    print_items(order.items)


def print_items(items: list[Item]) -> None:
    total = 0
    for item in items:
        print(f"  {item.name} x{item.qty} = {item.price * item.qty}")
        total += item.price * item.qty
    print(f"Total: {total}")
```

Caution: name the function for its intent, not its mechanics — `print_items`, not `loop_and_sum`.

### Inline Method

Drop a method whose body is as clear as its name and call the body directly. **When:** the indirection earns nothing, or you are flattening a structure before a larger rework.

**Before**

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Driver:
    late_deliveries: int


def rating(driver: Driver) -> int:
    return 2 if more_than_five_late_deliveries(driver) else 1


def more_than_five_late_deliveries(driver: Driver) -> bool:
    return driver.late_deliveries > 5
```

**After**

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Driver:
    late_deliveries: int


def rating(driver: Driver) -> int:
    return 2 if driver.late_deliveries > 5 else 1
```

Caution: do not inline a method that subclasses override — you would lose the polymorphism.

### Extract Variable

Assign a dense or repeated expression to a well-named variable that explains intent. **When:** a boolean has many operators, or a sub-expression names a domain concept.

**Before**

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Employee:
    seniority_years: int


@dataclass(frozen=True)
class Order:
    quantity: int
    item_price: int
    employee: Employee


def apply_discount(order: Order) -> None:
    print(f"discount applied to order of {order.quantity}")


def maybe_discount(order: Order) -> None:
    if (
        order.quantity > 100
        and order.item_price > 50
        and order.employee.seniority_years > 5
    ):
        apply_discount(order)
```

**After**

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Employee:
    seniority_years: int


@dataclass(frozen=True)
class Order:
    quantity: int
    item_price: int
    employee: Employee


def apply_discount(order: Order) -> None:
    print(f"discount applied to order of {order.quantity}")


def maybe_discount(order: Order) -> None:
    is_large_order = order.quantity > 100
    is_high_value = order.item_price > 50
    is_senior_employee = order.employee.seniority_years > 5
    if is_large_order and is_high_value and is_senior_employee:
        apply_discount(order)
```

Caution: name the variable for the concept it represents, never for its type.

### Replace Temp with Query

Replace a read-only local that caches an expression with a method, so the value is reusable and self-naming. **When:** the temp is assigned exactly once and never reassigned.

**Before**

```python
from __future__ import annotations


class Order:
    def __init__(self, quantity: int, item_price: int) -> None:
        self.quantity = quantity
        self.item_price = item_price

    def price(self) -> float:
        base_price = self.quantity * self.item_price
        discount = base_price * 0.05 if base_price > 1000 else 0.0
        return base_price - discount
```

**After**

```python
from __future__ import annotations


class Order:
    def __init__(self, quantity: int, item_price: int) -> None:
        self.quantity = quantity
        self.item_price = item_price

    def price(self) -> float:
        return self.base_price() - self.discount()

    def base_price(self) -> int:
        return self.quantity * self.item_price

    def discount(self) -> float:
        return self.base_price() * 0.05 if self.base_price() > 1000 else 0.0
```

Caution: only safe when the temp is never reassigned — otherwise the query is not equivalent.

### Replace Magic Number with Symbolic Constant

Give a bare literal a descriptive `SCREAMING_SNAKE_CASE` name. **When:** the literal encodes a domain rule or appears in more than one place.

**Before**

```python
from __future__ import annotations


def annual_salary(monthly_salary: int) -> int:
    return monthly_salary * 12


def apply_tax(amount: float) -> float:
    return amount * 1.2
```

**After**

```python
from __future__ import annotations

MONTHS_PER_YEAR = 12
VAT_MULTIPLIER = 1.2


def annual_salary(monthly_salary: int) -> int:
    return monthly_salary * MONTHS_PER_YEAR


def apply_tax(amount: float) -> float:
    return amount * VAT_MULTIPLIER
```

Caution: do not name self-evident literals — `range(2)` needs no `PAIR_SIZE`.

### Decompose Conditional

Extract a complex condition and each branch into descriptively named helpers. **When:** an `if`/`else` hides multi-line business rules and readers must trace logic to grasp intent.

**Before**

```python
from __future__ import annotations

from datetime import date

SUMMER_START = date(2026, 6, 1)
SUMMER_END = date(2026, 8, 31)
SUMMER_RATE, WINTER_RATE = 10, 14
SUMMER_SERVICE, WINTER_SERVICE = 5, 8


def charge(day: date, quantity: int) -> int:
    if SUMMER_START <= day <= SUMMER_END:
        return quantity * SUMMER_RATE + SUMMER_SERVICE
    return quantity * WINTER_RATE + WINTER_SERVICE
```

**After**

```python
from __future__ import annotations

from datetime import date

SUMMER_START = date(2026, 6, 1)
SUMMER_END = date(2026, 8, 31)
SUMMER_RATE, WINTER_RATE = 10, 14
SUMMER_SERVICE, WINTER_SERVICE = 5, 8


def charge(day: date, quantity: int) -> int:
    return summer_charge(quantity) if is_summer(day) else winter_charge(quantity)


def is_summer(day: date) -> bool:
    return SUMMER_START <= day <= SUMMER_END


def summer_charge(quantity: int) -> int:
    return quantity * SUMMER_RATE + SUMMER_SERVICE


def winter_charge(quantity: int) -> int:
    return quantity * WINTER_RATE + WINTER_SERVICE
```

### Replace Nested Conditional with Guard Clauses

Handle edge cases up front with early returns, leaving the happy path flat and last. **When:** a nested `if`/`else` chain buries the normal case.

**Before**

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Employee:
    is_separated: bool
    is_retired: bool
    base_pay: int


def retired_amount(employee: Employee) -> int:
    return employee.base_pay // 2


def normal_pay_amount(employee: Employee) -> int:
    return employee.base_pay


def pay_amount(employee: Employee) -> int:
    if employee.is_separated:
        result = 0
    else:
        if employee.is_retired:
            result = retired_amount(employee)
        else:
            result = normal_pay_amount(employee)
    return result
```

**After**

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Employee:
    is_separated: bool
    is_retired: bool
    base_pay: int


def retired_amount(employee: Employee) -> int:
    return employee.base_pay // 2


def normal_pay_amount(employee: Employee) -> int:
    return employee.base_pay


def pay_amount(employee: Employee) -> int:
    if employee.is_separated:
        return 0
    if employee.is_retired:
        return retired_amount(employee)
    return normal_pay_amount(employee)
```

Caution: guards should reject — keep each one a precondition, not a second happy path in disguise.

### Replace Conditional with Polymorphism

Move each branch of a type-switch into a subclass that owns its behavior. **When:** the same type check recurs and adding a kind means editing every switch.

**Before**

```python
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class BirdKind(Enum):
    EUROPEAN = "european"
    AFRICAN = "african"


@dataclass(frozen=True)
class Bird:
    kind: BirdKind
    coconuts: int


def speed(bird: Bird) -> int:
    if bird.kind is BirdKind.EUROPEAN:
        return 35
    return max(0, 40 - 2 * bird.coconuts)
```

**After**

```python
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


class Bird(ABC):
    @abstractmethod
    def speed(self) -> int: ...


class EuropeanSwallow(Bird):
    def speed(self) -> int:
        return 35


@dataclass(frozen=True)
class AfricanSwallow(Bird):
    coconuts: int

    def speed(self) -> int:
        return max(0, 40 - 2 * self.coconuts)
```

Caution: premature abstraction — only worth it once behavior genuinely varies by type in several places.

### Extract Class

Split a class with two reasons to change into two focused classes. **When:** a cohesive subset of fields and methods forms a distinct sub-concept.

**Before**

```python
from __future__ import annotations


class Person:
    def __init__(self, name: str, area_code: str, number: str) -> None:
        self.name = name
        self.office_area_code = area_code
        self.office_number = number

    def telephone(self) -> str:
        return f"({self.office_area_code}) {self.office_number}"
```

**After**

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class TelephoneNumber:
    area_code: str
    number: str

    def __str__(self) -> str:
        return f"({self.area_code}) {self.number}"


class Person:
    def __init__(self, name: str, office: TelephoneNumber) -> None:
        self.name = name
        self.office = office

    def telephone(self) -> str:
        return str(self.office)
```

### Move Method

Move a method to the class whose data it uses most. **When:** a method references another class more than its own, signalling misplaced responsibility.

**Before**

```python
from __future__ import annotations


class AccountType:
    def __init__(self, *, is_premium: bool) -> None:
        self.is_premium = is_premium


class Account:
    def __init__(self, account_type: AccountType, days_overdrawn: int) -> None:
        self.account_type = account_type
        self.days_overdrawn = days_overdrawn

    def overdraft_charge(self) -> float:
        if self.account_type.is_premium:
            base = 10.0
            return base + max(0, self.days_overdrawn - 7) * 0.85
        return self.days_overdrawn * 1.75
```

**After**

```python
from __future__ import annotations


class AccountType:
    def __init__(self, *, is_premium: bool) -> None:
        self.is_premium = is_premium

    def overdraft_charge(self, days_overdrawn: int) -> float:
        if self.is_premium:
            base = 10.0
            return base + max(0, days_overdrawn - 7) * 0.85
        return days_overdrawn * 1.75


class Account:
    def __init__(self, account_type: AccountType, days_overdrawn: int) -> None:
        self.account_type = account_type
        self.days_overdrawn = days_overdrawn

    def overdraft_charge(self) -> float:
        return self.account_type.overdraft_charge(self.days_overdrawn)
```

### Introduce Parameter Object

Replace a recurring cluster of parameters with one cohesive object — and give it the behavior that operates on it. **When:** the same arguments always travel together across signatures.

**Before**

```python
from __future__ import annotations


def readings_outside_range(readings: list[int], low: int, high: int) -> list[int]:
    return [r for r in readings if r < low or r > high]


def count_in_range(data: list[int], low: int, high: int) -> int:
    return sum(1 for n in data if low <= n <= high)
```

**After**

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class NumberRange:
    low: int
    high: int

    def includes(self, value: int) -> bool:
        return self.low <= value <= self.high


def readings_outside_range(readings: list[int], span: NumberRange) -> list[int]:
    return [r for r in readings if not span.includes(r)]


def count_in_range(data: list[int], span: NumberRange) -> int:
    return sum(1 for n in data if span.includes(n))
```

### Separate Query from Modifier

Split a method that both returns a value and mutates state into a pure query and a command (Command-Query Separation). **When:** callers cannot read the value without triggering the side effect.

**Before**

```python
from __future__ import annotations

SUSPECTS = ("Don", "John")


def send_alert() -> None:
    print("alert: suspect spotted")


def check_security(people: list[str]) -> str:
    found = ""
    for person in people:
        if person in SUSPECTS:
            send_alert()
            found = person
    return found
```

**After**

```python
from __future__ import annotations

SUSPECTS = ("Don", "John")


def send_alert() -> None:
    print("alert: suspect spotted")


def find_miscreant(people: list[str]) -> str:
    return next((person for person in people if person in SUSPECTS), "")


def send_alerts(people: list[str]) -> None:
    if any(person in SUSPECTS for person in people):
        send_alert()
```

Caution: the query must be genuinely pure — if reading still mutates, the split has not solved anything.

## Principles

- **Refactor before adding features.** Make the change easy first, then make the easy change. Bolting a feature onto tangled code compounds the tangle.
- **Small, safe steps; run tests after each.** Every refactoring is reversible and tiny. A green test suite between steps is what makes the move safe rather than a rewrite.
- **Boy Scout Rule.** Leave each module a little cleaner than you found it — a name fixed, a guard flattened — and quality trends upward without dedicated cleanup sprints.
- **Principle of Least Surprise.** Refactored code should read the way a competent reader expects: intent-named functions, no hidden side effects, the happy path last. Surprise is a defect.

## Source

Adapted from [Satcomx00-x00/skills-db](https://github.com/Satcomx00-x00/skills-db) (skills/code-quality, MIT); examples ported to Python. For deeper treatment, see the [Refactoring catalog at refactoring.guru](https://refactoring.guru/refactoring) and Martin Fowler's [*Refactoring*](https://martinfowler.com/books/refactoring.html).
