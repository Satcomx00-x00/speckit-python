# Observability & Operations

Diagnostics go through the `logging` module (libraries to a `NullHandler`), logs are structured with a correlation id, CI gates every change, and artifacts and migrations are immutable, traceable, and reversible.

## Contents

- Directives — the constitution rows for observability and operations.
- Patterns — logger not `print`, library `NullHandler`, structured logs + correlation id, safe error logging, CI gate.
- Checklist — what a reviewer confirms before merge.

## Directives

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | High | Use the `logging` module (or `structlog`), never `print`. Configure logging at the entry point; libraries log to a `NullHandler` and never configure global logging. |
| P2 | High | Logs are structured (event, context, outcome) and carry a correlation/request id across boundaries; errors include context and nothing sensitive. |
| P2 | High | CI runs format-check, lint, typecheck, and tests on every PR; failures block merge. Builds are reproducible from the lockfile. |
| P3 | High | Emit metrics and traces (OpenTelemetry where applicable) to a central stack; alert on real signal — error rate, latency, saturation. |
| P3 | High | Deploy immutable, versioned artifacts traceable to a commit; migrations are reviewed, reversible, and applied through one pipeline. |
| P3 | Medium | Health checks gate rollouts; document and rehearse the rollback path; back up stateful data and test restores. |
| P4 | Medium | Incident retrospectives are blameless, written, and produce dated action items with owners. |

## Patterns

### 1. Module logger, never `print`

Get a logger by `__name__`; emit diagnostics through it.

```python
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


def charge(order_id: str, amount_cents: int) -> None:
    logger.info("charging order", extra={"order_id": order_id, "cents": amount_cents})
```

- Do: `logger.info(...)` so output is leveled, routable, and filterable.
- Don't: `print(f"charging {order_id}")` — it bypasses configuration and levels.

### 2. Libraries attach a `NullHandler`

A library never configures global logging; it stays silent until the app opts in.

```python
from __future__ import annotations

import logging

# src/orders/__init__.py
logging.getLogger(__name__).addHandler(logging.NullHandler())
```

- Do: add a `NullHandler` so importing the library produces no output by default.
- Don't: call `logging.basicConfig(...)` inside a library and hijack the app's config.

### 3. Configure logging once, at the entry point

Only the application sets handlers, levels, and format.

```python
from __future__ import annotations

import logging


def configure_logging(*, level: int = logging.INFO) -> None:
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
```

- Do: call `configure_logging()` from `main()` exactly once.
- Don't: scatter `basicConfig` calls across modules so config order decides behavior.

### 4. Structured logs with a correlation id

Carry a request id through context so logs across boundaries correlate.

```python
from __future__ import annotations

import logging
from contextvars import ContextVar

_request_id: ContextVar[str] = ContextVar("request_id", default="-")
logger = logging.getLogger(__name__)


def log_event(event: str, **fields: object) -> None:
    logger.info(event, extra={"request_id": _request_id.get(), **fields})
```

- Do: attach `request_id` to every record so a request can be traced end to end.
- Don't: emit free-text logs with no shared id to join on.

### 5. Log errors with context, never secrets

Include enough to debug; exclude tokens, passwords, and full PII.

```python
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


def process(user_id: str, token: str) -> None:
    try:
        _do_work(token)
    except TimeoutError:
        logger.exception("work timed out", extra={"user_id": user_id})


def _do_work(token: str) -> None:
    del token  # used by the real implementation
```

- Do: log `user_id` and the failure; let `logger.exception` capture the traceback.
- Don't: log the `token` or full PII into the record.

## Checklist

- [ ] Diagnostics use `logging`/`structlog`, never `print`.
- [ ] Logging is configured once at the application entry point.
- [ ] Libraries attach a `NullHandler` and never configure global logging.
- [ ] Logs are structured and carry a correlation/request id across boundaries.
- [ ] Error logs include context but never secrets, tokens, or full PII.
- [ ] CI runs format-check, lint, typecheck, and tests on every PR; failures block merge.
- [ ] Deploy artifacts are immutable, versioned, and traceable to a commit.
- [ ] Migrations are reviewed, reversible, and applied through one pipeline; rollback is rehearsed.
