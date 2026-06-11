# Data, Validation & Boundaries

Untrusted input is parsed into a typed model at every boundary, then trusted; downstream code never sees a raw `dict` or unparsed string.

## Contents

- Directives — the constitution rows for data and boundaries.
- Patterns — parse-don't-validate, schema validation, typed settings, DTOs, `Result` for expected failures.
- Checklist — what a reviewer confirms before merge.

## Directives

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | Parse, don't validate — convert untrusted input into a typed model at the boundary, then trust the type. |
| P2 | Critical | Validate every external input (HTTP body, params, CLI args, env, files, queue messages, third-party responses) with a schema. |
| P2 | Critical | Validate configuration and environment at startup with a typed settings model; fail fast and loudly. |
| P2 | High | Define DTOs that decouple internal domain models from API/wire shapes; never serialize a persistence model to the client. |
| P2 | High | Never trust runtime types across a process boundary — the schema is the contract. |
| P3 | High | Generate types/schemas from the single source of truth (DB schema, OpenAPI, protobuf); never hand-sync. |
| P3 | Medium | Return `Result[T, E]`-style values (or a narrow exception) for *expected* failures; reserve exceptions for the unexpected. |

## Patterns

### 1. Parse, don't validate

Return a typed model from the boundary so callers cannot forget a check.

```python
from __future__ import annotations

from pydantic import BaseModel, EmailStr, Field


class SignupRequest(BaseModel):
    email: EmailStr
    age: int = Field(ge=0, le=130)


def parse_signup(payload: object) -> SignupRequest:
    return SignupRequest.model_validate(payload)
```

- Do: return a `SignupRequest`; the rest of the code receives a validated value.
- Don't: pass `payload: dict[str, object]` inward and re-check fields everywhere.

### 2. Typed settings, validated at startup

Read the environment once into a model; fail fast if it is malformed.

```python
from __future__ import annotations

import os

from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = Field(min_length=1)
    pool_size: int = Field(default=10, ge=1, le=100)
    request_timeout_seconds: float = Field(default=5.0, gt=0)


def load_settings() -> Settings:
    # Reads the environment once; raises loudly on missing/malformed values.
    return Settings.model_validate(dict(os.environ))
```

- Do: centralize config in `Settings` and load it at the entry point.
- Don't: call `os.environ["DATABASE_URL"]` deep inside a service.

### 3. DTOs decouple wire shape from the domain

Map domain to an explicit output model so internals never leak.

```python
from __future__ import annotations

from dataclasses import dataclass

from pydantic import BaseModel


@dataclass(frozen=True)
class Order:  # domain, includes internal fields
    id: str
    total_cents: int
    internal_risk_score: float


class OrderOut(BaseModel):  # wire DTO, public fields only
    id: str
    total_cents: int


def to_order_out(order: Order) -> OrderOut:
    return OrderOut(id=order.id, total_cents=order.total_cents)
```

- Do: expose `OrderOut`; `internal_risk_score` never reaches the client.
- Don't: serialize `Order` directly and leak internal fields.

### 4. `Result` for expected failures

Model an expected failure (not found, invalid) as data the caller must handle.

```python
from __future__ import annotations

from dataclasses import dataclass
from typing import Generic, TypeVar

T = TypeVar("T")
E = TypeVar("E")


@dataclass(frozen=True)
class Ok(Generic[T]):
    value: T


@dataclass(frozen=True)
class Err(Generic[E]):
    error: E


Result = Ok[T] | Err[E]


def parse_quantity(raw: str) -> Result[int, str]:
    if not raw.isdigit():
        return Err("not a number")
    return Ok(int(raw))
```

- Do: return `Result[int, str]`; the caller pattern-matches `Ok`/`Err`.
- Don't: raise for an expected, recoverable input error on the happy path.

### 5. Narrow at the boundary, trust within

Convert a hostile `object` into a domain type once, at the edge.

```python
from __future__ import annotations

from typing import NewType

CustomerId = NewType("CustomerId", str)


def parse_customer_id(raw: object) -> CustomerId:
    if not isinstance(raw, str) or not raw.startswith("cust_"):
        msg = f"invalid customer id: {raw!r}"
        raise ValueError(msg)
    return CustomerId(raw)
```

- Do: parse `raw: object` into a `CustomerId` at the boundary.
- Don't: thread `raw: object` through the service and check it repeatedly.

## Checklist

- [ ] Every external input is parsed into a typed model at the boundary, not re-validated inward.
- [ ] Configuration loads once into a typed settings model that fails fast on bad values.
- [ ] No `os.environ[...]` reads buried in business logic.
- [ ] Persistence rows are mapped to DTOs; internal fields never reach the wire.
- [ ] Expected failures return a `Result`/narrow type; exceptions are reserved for the unexpected.
- [ ] Types are generated from the single source of truth where one exists; no hand-synced parallel schemas.
- [ ] No raw `dict[str, Any]`/`str` flows from a boundary into the domain core.
