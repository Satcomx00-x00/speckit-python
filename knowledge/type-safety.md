# Type Safety & Static Analysis

The type checker is the first test suite: the whole package and its tests check clean under `mypy --strict`, with no escape hatches.

## Contents

- Directives — the constitution rows for typing.
- Patterns — `NewType` ids, `Protocol` seams, `Literal`/`assert_never`, narrowing without `Any`, `TYPE_CHECKING`.
- Checklist — what a reviewer confirms before merge.

## Directives

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | Run `mypy --strict` (or pyright `strict`) over the whole package; type errors fail CI. |
| P1 | Critical | Ban `Any` in public signatures; use precise types, `object` + narrowing, or a `Protocol`. |
| P1 | Critical | Annotate every function — parameters and return — including `-> None`; no implicitly-typed public API. |
| P1 | High | Ban bare `# type: ignore`; require `# type: ignore[code]  # reason`. |
| P1 | High | Enable `warn_unused_ignores`, `warn_redundant_casts`, `disallow_untyped_defs`, `no_implicit_optional`. |
| P2 | High | Reserve `cast()` for genuinely un-expressible narrowing; never to paper over a real error. |
| P2 | High | Use `TYPE_CHECKING` + `from __future__ import annotations` to avoid import cycles and runtime typing cost. |
| P2 | High | Use `Protocol` for dependency seams; depend on the narrowest protocol a consumer needs. |
| P2 | Medium | Prefer `NewType` / branded aliases for ids and tokens over raw `str`. |
| P2 | Medium | Use `Literal`, `Enum`, and `assert_never` to make illegal states unrepresentable and switches exhaustive. |
| P3 | Medium | Ship `py.typed` for any installed/published package. |
| P3 | Medium | Keep `mypy` clean on the test suite too. |

## Patterns

### 1. Branded ids over raw `str`

A `NewType` makes mixing a `UserId` with an `OrderId` a type error at no runtime cost.

```python
from __future__ import annotations

from typing import NewType

UserId = NewType("UserId", str)
OrderId = NewType("OrderId", str)


def cancel_order(user: UserId, order: OrderId) -> None:
    del user, order  # placeholder for the real work
```

- Do: `def cancel_order(user: UserId, order: OrderId) -> None`.
- Don't: `def cancel_order(user: str, order: str) -> None` — the two are interchangeable.

### 2. `Protocol` seams instead of `Any`

Depend on the narrowest structural type a consumer needs.

```python
from __future__ import annotations

from typing import Protocol


class Clock(Protocol):
    def now_epoch(self) -> float: ...


def is_expired(*, issued_at: float, ttl_seconds: float, clock: Clock) -> bool:
    return clock.now_epoch() - issued_at > ttl_seconds
```

- Do: accept a `Clock` Protocol so any conforming object works.
- Don't: accept `clock: Any` or import a concrete clock inside the function.

### 3. Exhaustive matching with `Literal` and `assert_never`

`assert_never` turns a forgotten case into a compile-time error.

```python
from __future__ import annotations

from typing import Literal, assert_never

Status = Literal["pending", "shipped", "delivered"]


def label(status: Status) -> str:
    match status:
        case "pending":
            return "Awaiting dispatch"
        case "shipped":
            return "In transit"
        case "delivered":
            return "Complete"
    assert_never(status)
```

- Do: end the `match` with `assert_never(status)`; adding a state breaks the build.
- Don't: add an `else: return "?"` that silently swallows new states.

### 4. Narrow `object`, never reach for `Any`

For genuinely dynamic input, type it `object` and narrow with `isinstance`.

```python
from __future__ import annotations


def to_port(raw: object) -> int:
    if isinstance(raw, int):
        return raw
    if isinstance(raw, str) and raw.isdigit():
        return int(raw)
    msg = f"not a port: {raw!r}"
    raise ValueError(msg)
```

- Do: take `raw: object` and narrow; the checker tracks the refinement.
- Don't: take `raw: Any` — every downstream use is then unchecked.

### 5. Typing-only imports behind `TYPE_CHECKING`

Break import cycles and avoid runtime import cost for symbols used only in annotations.

```python
from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Sequence

    from myapp.domain import Order


def total_cents(orders: Sequence[Order]) -> int:
    return sum(order.amount_cents for order in orders)
```

- Do: guard typing-only imports with `if TYPE_CHECKING:` plus the `__future__` import.
- Don't: import a heavy or cyclic module at runtime just to annotate a parameter.

## Checklist

- [ ] `mypy --strict` passes over `src/` and `tests/` with zero errors.
- [ ] No `Any` in any public signature; dynamic input is `object` + narrowing or a `Protocol`.
- [ ] Every function is fully annotated, including `-> None`.
- [ ] Each `# type: ignore` carries `[code]` and a reason; `warn_unused_ignores` is on.
- [ ] `cast()` appears only where the narrowing is genuinely un-expressible, with a comment.
- [ ] Ids, tokens, and money use `NewType`/value objects, not bare `str`/`int`.
- [ ] Closed sets use `Literal`/`Enum` and exhaust with `assert_never`.
- [ ] Installed/published packages ship a `py.typed` marker.
