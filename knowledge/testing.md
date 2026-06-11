# Testing

The pure core is unit-tested with zero mocks because effects are injected; tests are deterministic, behavior-focused, and a regression test follows every fixed bug.

## Contents

- Directives — the constitution rows for testing.
- Patterns — pure unit tests without mocks, injected clock/RNG, fixtures, parametrization, Hypothesis.
- Checklist — what a reviewer confirms before merge.

## Directives

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | Tests run under pytest and pass deterministically in CI on every change; a red suite blocks merge. |
| P2 | Critical | Unit-test the pure core with zero mocks; cover happy path, boundaries, and documented error paths. |
| P2 | High | Test behavior and contracts, not implementation details; avoid asserting on private internals. |
| P2 | High | Make tests deterministic: inject the clock and RNG, freeze time, seed randomness; no network/wall-clock/order dependence. |
| P2 | Medium | Use fixtures for setup and parametrization for input matrices; one behavior per test with a clear arrange/act/assert shape. |
| P3 | High | Add integration tests at real boundaries (DB, HTTP, filesystem) using ephemeral resources; never a shared mutable environment. |
| P3 | Medium | Property-based tests (Hypothesis) for parsers, serializers, and invariant-heavy logic; a fixed regression test for every fixed bug. |
| P3 | Medium | Coverage does not regress against the baseline; new code ships with tests; don't game coverage. |

## Patterns

### 1. Pure unit test, no mocks

A pure function takes inputs and returns outputs; the test needs nothing else.

```python
from __future__ import annotations


def discounted(price_cents: int, *, percent_off: int) -> int:
    if not 0 <= percent_off <= 100:
        msg = "percent_off out of range"
        raise ValueError(msg)
    return price_cents * (100 - percent_off) // 100


def test_discounted_applies_percentage() -> None:
    assert discounted(1000, percent_off=25) == 750
```

- Do: call the pure function directly and assert on the result.
- Don't: patch globals or mock collaborators a pure function never touches.

### 2. Inject the clock instead of patching time

Determinism comes from passing a fake clock, not freezing the system clock.

```python
from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


class Clock(Protocol):
    def now_epoch(self) -> float: ...


@dataclass(frozen=True)
class FixedClock:
    value: float

    def now_epoch(self) -> float:
        return self.value


def is_expired(issued_at: float, ttl: float, *, clock: Clock) -> bool:
    return clock.now_epoch() > issued_at + ttl


def test_is_expired_at_boundary() -> None:
    clock = FixedClock(value=150.0)
    assert is_expired(100.0, 40.0, clock=clock) is True
```

- Do: inject a `FixedClock`; the result is deterministic.
- Don't: rely on `time.time()` and a `sleep` to cross the boundary.

### 3. Parametrize the input matrix

One test body, many cases, each independently reported.

```python
from __future__ import annotations

import pytest


def normalize_email(raw: str) -> str:
    return raw.strip().lower()


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("  A@B.com ", "a@b.com"),
        ("user@Example.COM", "user@example.com"),
    ],
)
def test_normalize_email(raw: str, expected: str) -> None:
    assert normalize_email(raw) == expected
```

- Do: parametrize boundary and representative cases.
- Don't: copy-paste five near-identical test functions.

### 4. Assert error paths explicitly

Document and verify the failure contract.

```python
from __future__ import annotations

import pytest


def parse_age(raw: str) -> int:
    value = int(raw)
    if value < 0:
        msg = "age must be non-negative"
        raise ValueError(msg)
    return value


def test_parse_age_rejects_negative() -> None:
    with pytest.raises(ValueError, match="non-negative"):
        parse_age("-1")
```

- Do: assert the raised type and message with `pytest.raises`.
- Don't: leave error paths untested because "they shouldn't happen".

### 5. Property-based test for an invariant

Hypothesis explores inputs a fixed example set would miss.

```python
from __future__ import annotations

from hypothesis import given
from hypothesis import strategies as st


def round_trip(value: int) -> int:
    return int(str(value))


@given(st.integers())
def test_round_trip_is_identity(value: int) -> None:
    assert round_trip(value) == value
```

- Do: state the invariant and let Hypothesis search for a counterexample.
- Don't: assume two hand-picked examples prove a round-trip holds.

## Checklist

- [ ] The suite runs under pytest, is deterministic, and is green in CI on every change.
- [ ] The pure core is unit-tested with zero mocks; effects are injected.
- [ ] Tests assert behavior and contracts, not private internals.
- [ ] The clock and RNG are injected; time is frozen and randomness seeded.
- [ ] Fixtures handle setup; parametrization covers the input matrix.
- [ ] Happy path, boundaries, and documented error paths are all covered.
- [ ] Integration tests use ephemeral resources, never a shared mutable environment.
- [ ] Every fixed bug has a regression test; coverage does not regress.
