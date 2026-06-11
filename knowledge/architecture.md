# Architecture & Design

Business logic is a pure, deterministic core; I/O, clocks, and randomness live in a thin imperative shell and are injected through `Protocol` seams.

## Contents

- Directives — the constitution rows for architecture.
- Patterns — pure core, injected dependencies, `Protocol` seams, domain vs persistence vs wire types, composition.
- Checklist — what a reviewer confirms before merge.

## Directives

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | Pure core, imperative shell: business logic is side-effect-free and dependency-injected; I/O lives at the edges. |
| P1 | High | DIP — high-level logic depends on abstractions (`Protocol`/ABC), not concretions. Inject DB, clock, RNG, HTTP client, logger. |
| P1 | High | SRP / OCP — one reason to change; extend via new functions/strategies, not by editing stable ones. |
| P2 | High | Define domain types distinct from persistence rows and from wire/DTO shapes; map between layers explicitly. |
| P2 | High | Composition over inheritance; deep class hierarchies are a smell. |
| P2 | High | ISP / LSP — split fat interfaces into role-specific protocols; subtypes honor the parent contract. |
| P2 | Medium | Keep modules acyclic; ban circular imports. One public re-export boundary per package. |
| P3 | Medium | Referential transparency where feasible; prefer immutable dataclasses (`frozen=True`) and tuples for value objects. |

## Patterns

### 1. Inject the clock; keep the core pure

The core takes its effects as arguments, so it is deterministic and testable without mocks.

```python
from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


class Clock(Protocol):
    def now_epoch(self) -> float: ...


@dataclass(frozen=True)
class Session:
    issued_at: float
    ttl_seconds: float


def session_active(session: Session, *, clock: Clock) -> bool:
    return clock.now_epoch() < session.issued_at + session.ttl_seconds
```

- Do: pass `clock` in; the function is a pure mapping of inputs to a `bool`.
- Don't: call `time.time()` inside `session_active` — that couples logic to the wall clock.

### 2. Depend on a narrow `Protocol` (DIP + ISP)

A service depends on the role it needs, not a concrete repository.

```python
from __future__ import annotations

from typing import Protocol

from myapp.domain import User, UserId


class UserReader(Protocol):
    def get(self, user_id: UserId) -> User | None: ...


def display_name(user_id: UserId, *, reader: UserReader) -> str:
    user = reader.get(user_id)
    return user.name if user is not None else "unknown"
```

- Do: depend on `UserReader` (read-only role) — any adapter satisfying it works.
- Don't: import a concrete `PostgresUserRepository` into the service.

### 3. Separate domain, persistence, and wire types

Three shapes, three responsibilities, mapped explicitly.

```python
from __future__ import annotations

from dataclasses import dataclass

from pydantic import BaseModel


@dataclass(frozen=True)
class User:  # domain
    id: str
    email: str


@dataclass(frozen=True)
class UserRow:  # persistence
    id: str
    email: str
    created_at: float


class UserOut(BaseModel):  # wire / DTO
    id: str
    email: str


def row_to_domain(row: UserRow) -> User:
    return User(id=row.id, email=row.email)


def domain_to_wire(user: User) -> UserOut:
    return UserOut(id=user.id, email=user.email)
```

- Do: map `UserRow -> User -> UserOut` so `created_at` never leaks to the client.
- Don't: serialize `UserRow` straight to the response.

### 4. Composition over inheritance

Compose behavior from small protocols instead of building a base-class tower.

```python
from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


class Notifier(Protocol):
    def send(self, to: str, body: str) -> None: ...


@dataclass(frozen=True)
class WelcomeFlow:
    notifier: Notifier

    def run(self, email: str) -> None:
        self.notifier.send(email, "Welcome aboard")
```

- Do: hold a `Notifier` and delegate (composition).
- Don't: subclass `EmailNotifier` to get its `send` — inheritance for reuse couples you to it.

### 5. Immutable value objects

`frozen=True` dataclasses make accidental mutation a type error.

```python
from __future__ import annotations

from dataclasses import dataclass, replace


@dataclass(frozen=True)
class Money:
    cents: int
    currency: str


def add(a: Money, b: Money) -> Money:
    if a.currency != b.currency:
        msg = "currency mismatch"
        raise ValueError(msg)
    return replace(a, cents=a.cents + b.cents)
```

- Do: return a new `Money` via `replace(...)`.
- Don't: mutate `a.cents += b.cents` — value objects are immutable.

## Checklist

- [ ] Business logic is pure: no I/O, clock, RNG, or global state reached for mid-computation.
- [ ] Every effect (DB, clock, RNG, HTTP, logger) is injected, typed as a narrow `Protocol`.
- [ ] Domain, persistence, and wire types are distinct, with explicit mapping functions.
- [ ] Behavior is composed from small protocols; class hierarchies stay shallow.
- [ ] Subtypes honor the parent contract (no surprise raises, no narrowed inputs).
- [ ] No circular imports; at most one public re-export boundary per package.
- [ ] Value objects are `frozen=True`; mutation is opt-in, not the default.
