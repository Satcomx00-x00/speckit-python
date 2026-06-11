# Error Handling & Resilience

Expected failure is modeled in the types and handled at a deliberate boundary; exceptions are narrow, causal, and reserved for the genuinely exceptional.

## Contents

- Directives — the constitution rows for errors and resilience.
- Patterns — narrowest `except`, typed error hierarchy, `raise ... from`, context managers, timeouts, bounded retries.
- Checklist — what a reviewer confirms before merge.

## Directives

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | Ban bare `except:` and silent `except Exception: pass`; catch the narrowest exception and handle it deliberately. |
| P2 | High | Model domain errors as a small typed exception hierarchy or a `Result` union — not generic `Exception("...")` strings. |
| P2 | High | Preserve causality with `raise NewError(...) from err`; never swallow the original traceback. |
| P2 | High | Catch exceptions where you can act on them; let unexpected errors surface to one top-level boundary that logs and returns a safe response. |
| P2 | Medium | Use context managers (or `try/finally`) so resources are always released, including on error. |
| P3 | High | Explicit timeouts on every network/DB call; bounded retries with backoff for idempotent operations; fail fast for hard-down dependencies. |
| P3 | Medium | Make operations idempotent where feasible; guard non-idempotent side effects with idempotency keys. |

## Patterns

### 1. Catch the narrowest exception

Handle the specific failure you understand; let the rest propagate.

```python
from __future__ import annotations

from pathlib import Path


def read_config_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return "{}"  # a missing config is an expected, handled case
```

- Do: catch `FileNotFoundError` and respond meaningfully.
- Don't: `except Exception: pass` — that hides permission errors and decode failures.

### 2. A small typed error hierarchy

Give the caller a type to match on, not a string to parse.

```python
from __future__ import annotations


class OrderError(Exception):
    """Base class for order domain errors."""


class OrderNotFound(OrderError):
    def __init__(self, order_id: str) -> None:
        super().__init__(f"order not found: {order_id}")
        self.order_id = order_id


class PaymentDeclined(OrderError):
    def __init__(self, reason: str) -> None:
        super().__init__(f"payment declined: {reason}")
        self.reason = reason
```

- Do: define `OrderNotFound`/`PaymentDeclined` under one base.
- Don't: raise `Exception("order 42 not found")` the caller must string-match.

### 3. Preserve the cause with `raise ... from`

Wrap a low-level error without discarding its traceback.

```python
from __future__ import annotations


class ConfigError(Exception):
    pass


def parse_port(raw: str) -> int:
    try:
        return int(raw)
    except ValueError as err:
        msg = f"invalid port: {raw!r}"
        raise ConfigError(msg) from err
```

- Do: `raise ConfigError(...) from err` — the chain is preserved.
- Don't: `raise ConfigError(...)` alone, losing the original cause.

### 4. Context managers release resources

`with` guarantees cleanup, including on the error path.

```python
from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from threading import Lock


@contextmanager
def acquired(lock: Lock) -> Iterator[None]:
    lock.acquire()
    try:
        yield
    finally:
        lock.release()
```

- Do: release in `finally` (or rely on `with`) so the lock is never leaked.
- Don't: `lock.acquire()` then `lock.release()` with work in between that may raise.

### 5. Timeouts and bounded retries for idempotent work

Cap both the wait and the number of attempts; back off between them.

```python
from __future__ import annotations

from collections.abc import Callable
from typing import Protocol, TypeVar

T = TypeVar("T")


class Sleeper(Protocol):
    def sleep(self, seconds: float) -> None: ...


def with_retries(op: Callable[[], T], *, attempts: int, sleeper: Sleeper) -> T:
    last: TimeoutError | None = None
    for attempt in range(attempts):
        try:
            return op()
        except TimeoutError as err:  # only retry the transient error
            last = err
            sleeper.sleep(2.0**attempt)
    raise RuntimeError("retries exhausted") from last
```

- Do: bound attempts, back off, and only retry idempotent, transient failures.
- Don't: loop forever, or retry a `PaymentDeclined` that will never succeed.

## Checklist

- [ ] No bare `except:` and no `except Exception: pass` anywhere.
- [ ] The narrowest meaningful exception is caught at each handler.
- [ ] Domain errors form a small typed hierarchy (or `Result`), not generic strings.
- [ ] Wrapped errors use `raise NewError(...) from err`; the cause is preserved.
- [ ] Resources are released via context managers or `try/finally`.
- [ ] Every network/DB call has an explicit timeout.
- [ ] Retries are bounded with backoff and applied only to idempotent operations.
- [ ] Unexpected errors reach a single top-level boundary that logs safely.
