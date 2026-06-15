---
name: speckit-feature
description: "Stack-agnostic, end-to-end Python feature scaffold. FIRST runs an interactive clarification round (up to 5 high-impact questions, each with a recommended default) to remove ambiguity, then walks a layered slice: typed contracts (Pydantic/dataclass) → domain models → repository Protocol + adapter → pure Result-returning services (dependency-injected) → interface layer (API route / CLI command / library function) → wiring & side effects → pytest unit + integration tests. Every file is mypy --strict clean, Ruff-clean, and compliant with the project constitution. Use when the user wants to build or scaffold a new Python feature end-to-end."
---

# Speckit Feature

> This skill is generated from the Python preset command
> `presets/python/commands/speckit.feature.md` by `scripts/build-skills.py`.
> Edit the command (or the knowledge map in the generator), then regenerate.

## User Input

```text
$ARGUMENTS
```

Parse the first positional argument as the **feature name** — a `snake_case` slug for modules and a derived `PascalCase` for types (e.g. `invoice_export` → `InvoiceExport`).

Optional flags (combinable):

| Flag | Meaning | Default |
|---|---|---|
| `--description <text>` | One-line feature description | `""` |
| `--surface <kind>` | Interface surface: `api` (web route) · `cli` (command) · `lib` (public function) · `worker` (queue/task) | inferred from repo |
| `--fields <list>` | Comma-separated `name:type` field definitions | inferred / asked |
| `--package <path>` | Source package root | inferred (`src/<pkg>` or `<pkg>`) |
| `--async` / `--sync` | Async or sync I/O style | inferred from repo |
| `--validation <lib>` | Boundary parsing: `pydantic` · `dataclass` · `attrs` | inferred (`pydantic` if present) |
| `--error-style <s>` | `result` (typed `Result[T, E]`) · `exceptions` (typed hierarchy) | `result` |
| `--no-clarify` | Skip the clarification round (NOT recommended) | run clarification |
| `--skip-tests` | Skip the test phase | generate tests |
| `--only <phases>` | Comma-separated phases to run (e.g. `1,2,3`) | all phases |
| `--dry-run` | Print file contents instead of writing | write files |

If the feature name is missing, ask for it before proceeding.

---

## Pre-Execution Checks

1. Check for `.specify/extensions.yml`. If present, look for hooks under `hooks.before_feature` and apply standard hook-processing (skip disabled, surface optional as instructions, auto-execute mandatory).
2. Detect the project shape so the scaffold matches it (do **not** impose a layout the repo doesn't use):
   - Source layout: `src/<pkg>/` vs flat `<pkg>/`. Read `pyproject.toml` `[project]` / `[tool.*]`.
   - Surface signals: a web framework (`fastapi`, `flask`, `django`, `litestar`) → `api`; `typer`/`click`/`argparse` → `cli`; `[project.scripts]` console entry → `cli`; a `celery`/`rq`/`arq`/`dramatiq` dependency → `worker`; otherwise → `lib`.
   - Async signals: `async def` already present, an ASGI server, `httpx.AsyncClient`, `asyncpg` → async; otherwise sync.
   - Validation lib: `pydantic` present → `pydantic`; else stdlib `dataclasses`.
   - Test layout: `tests/` location and `conftest.py` conventions.
3. If the constitution is missing (`.specify/memory/constitution.md`), note it and recommend `/speckit-constitution-scan` first — scaffolds should reference real directives. Proceed if the user insists.

---

## Phase 0 — Clarify (interactive, default ON)

> **This is the quality gate.** A feature scaffolded from an ambiguous one-liner produces TODO-riddled boilerplate; a feature scaffolded after five sharp questions produces code that fits. Run this phase **before generating any file** unless `--no-clarify` is passed (warn that downstream rework risk increases when skipped).

### 0.1 — Ambiguity scan

Read `$ARGUMENTS`, the detected project shape, and (if present) the constitution and the current spec/plan. Scan for ambiguity across this taxonomy and mark each **Clear / Partial / Missing** (keep the map internal):

- **Domain & data** — entities, fields and their types, identity/uniqueness, lifecycle/state transitions, invariants.
- **Behavior & scope** — the core operations (create/read/update/list/delete/compute/…), success criteria, explicit non-goals.
- **Boundary & contract** — surface (API/CLI/lib/worker), input shape and validation rules, output/DTO shape, error cases the caller must handle.
- **Persistence & integrations** — storage (DB/file/in-memory/none), external services and their failure modes, transactionality.
- **Non-functional** — async vs sync, concurrency/idempotency needs, performance/volume expectations, security/authz, observability.
- **Edge cases** — empty/oversized inputs, conflicts, timeouts, partial failure, Unicode, time zones.

### 0.2 — Build a prioritized question queue (max 5)

Generate (internally) up to **5** questions, ranked by **(Impact × Uncertainty)**. Only ask questions whose answers materially change the data model, the layer boundaries, the error taxonomy, the test design, or the security posture. Exclude anything already answered, trivially stylistic, or better deferred to `/speckit-plan`. If fewer than 5 areas are genuinely unresolved, ask fewer. If nothing material is unresolved, skip the loop and say so.

### 0.3 — Ask ONE question at a time, with a recommendation

For **each** question, present exactly one at a time. Always lead with **your recommended answer and a one-line reason**, then the options as a table:

```
**Recommended:** <option> — <one-line reasoning grounded in the constitution / Python best practice>

| Option | Description |
|--------|-------------|
| A | <option A> |
| B | <option B> |
| C | <option C>  (add D/E up to 5 as needed) |
| Short | Provide your own short answer (≤ 5 words) |

Reply with a letter (e.g. "A"), say "yes"/"recommended" to accept the recommendation, or give your own short answer.
```

For a question with no meaningful discrete options, give a **Suggested:** answer with brief reasoning and accept a `≤ 5 word` free-form reply.

Rules:
- Never reveal future queued questions in advance.
- If the answer is ambiguous, ask one quick disambiguation (it does not count as a new question).
- Stop early when all critical ambiguities are resolved, or the user says "done"/"proceed"/"stop", or you reach 5 asked questions.
- Use the answers to fill the scaffold concretely — **do not** leave a `# TODO` for something the user just answered.

> When this command runs in an environment with a structured question UI (e.g. Claude Code's question tool), you MAY batch the questions into that UI instead of the one-at-a-time text loop — but keep the same "recommended option first" framing and the same ≤ 5 cap.

### 0.4 — Echo the resolved decisions

Before scaffolding, print a compact **Feature Decision Record** the rest of the run is bound by, and (if a spec file exists) append the Q→A pairs under a `## Clarifications` / `### Session YYYY-MM-DD` block per the clarify convention:

```
## Feature Decisions — <feature_name>
- Surface: <api | cli | lib | worker>
- Entity & fields: <Name { field: type, ... }>
- Operations: <create, list, get, update, delete, ...>
- Persistence: <postgres | sqlite | file | in-memory | none>
- I/O style: <async | sync>
- Validation: <pydantic | dataclass | attrs>
- Error style: <result | exceptions>
- Key constraints: <invariants, authz, idempotency, limits>
- Non-goals: <...>
```

---

## Feature Scaffold

Each phase below adapts to the Phase-0 decisions. Generate concrete code — fully type-annotated, `mypy --strict` clean, Ruff-clean. Use `<feature>` for the snake_case slug, `<Feature>` for the PascalCase type, `<pkg>` for the package root.

### Phase 1 — Typed Contracts (boundary models)

**Goal**: Parse-don't-validate models for input and output, the single source of truth for the feature's shapes.

**Generate**: `<pkg>/<feature>/contracts.py`

```python
"""Boundary contracts for the <feature> feature.

These models are the parse-don't-validate layer: untrusted input becomes a
typed value here, and downstream code trusts the type. Output DTOs decouple
the wire shape from the internal domain model.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum

from pydantic import BaseModel, ConfigDict, Field  # if --validation pydantic
# (dataclass variant: use @dataclass(frozen=True, slots=True) + explicit validators)


class <Feature>Status(str, Enum):
    """Lifecycle states for a <Feature>. Make illegal states unrepresentable."""

    DRAFT = "draft"
    ACTIVE = "active"
    ARCHIVED = "archived"


class Create<Feature>Input(BaseModel):
    """Validated input for creating a <Feature>. Every field is constrained."""

    model_config = ConfigDict(frozen=True, extra="forbid")

    # Fields resolved from Phase 0 — precise constraints, never bare str/int:
    name: str = Field(min_length=1, max_length=255)
    # status defaults are domain decisions, not input — set in the service.


class Update<Feature>Input(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")

    name: str | None = Field(default=None, min_length=1, max_length=255)


class <Feature>DTO(BaseModel):
    """What callers receive. Omits secrets/internal-only fields."""

    model_config = ConfigDict(frozen=True)

    id: str
    name: str
    status: <Feature>Status
    created_at: datetime
    updated_at: datetime
```

**Checklist**:
- [ ] Every input field carries a precise constraint (length, range, pattern, enum) — no bare `str`/`int`/`Any`.
- [ ] `extra="forbid"` (or equivalent) so unknown keys are rejected, not silently dropped.
- [ ] Output DTO omits secrets, hashes, and internal-only fields.
- [ ] Models are frozen/immutable where they represent values.

### Phase 2 — Domain Model

**Goal**: The internal representation, distinct from wire and persistence shapes. Pure data + pure invariants.

**Generate**: `<pkg>/<feature>/models.py`

```python
"""Domain model for <feature> — internal representation and invariants."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import NewType

from .contracts import <Feature>Status

<Feature>Id = NewType("<Feature>Id", str)  # branded — never a raw str


@dataclass(frozen=True, slots=True)
class <Feature>:
    """A <Feature> aggregate. Immutable; transitions return new instances."""

    id: <Feature>Id
    name: str
    status: <Feature>Status
    created_at: datetime
    updated_at: datetime

    def archived(self, *, now: datetime) -> <Feature>:
        """Return an archived copy. Pure state transition — no I/O."""
        from dataclasses import replace

        return replace(self, status=<Feature>Status.ARCHIVED, updated_at=now)
```

**Checklist**:
- [ ] IDs are branded (`NewType`), not raw `str`.
- [ ] State transitions are pure methods returning new instances — no I/O, no clock, no RNG inside.
- [ ] Domain model is distinct from `contracts.py` (wire) and the persistence row.

### Phase 3 — Repository Protocol + Adapter

**Goal**: A `Protocol` the service depends on (DIP), plus a concrete adapter for the chosen store. The service never imports the DB driver.

**Generate**: `<pkg>/<feature>/repository.py`

```python
"""Persistence seam for <feature>.

`<Feature>Repository` is the abstraction the service depends on. Concrete
adapters (SQL, in-memory, file) implement it. Swapping the store never touches
business logic.
"""

from __future__ import annotations

from typing import Protocol

from .contracts import Create<Feature>Input
from .models import <Feature>, <Feature>Id


class <Feature>Repository(Protocol):
    """The narrowest interface the service needs. Structural typing."""

    async def get(self, id: <Feature>Id) -> <Feature> | None: ...
    async def list(self, *, limit: int, cursor: <Feature>Id | None) -> list[<Feature>]: ...
    async def add(self, data: Create<Feature>Input) -> <Feature>: ...
    async def save(self, entity: <Feature>) -> <Feature>: ...
    async def delete(self, id: <Feature>Id) -> None: ...


class InMemory<Feature>Repository:
    """Reference adapter — used by unit/integration tests and local runs.

    Implements `<Feature>Repository` structurally (no inheritance needed).
    Replace with a SQL adapter for production; the service is unchanged.
    """

    def __init__(self) -> None:
        self._store: dict[<Feature>Id, <Feature>] = {}

    async def get(self, id: <Feature>Id) -> <Feature> | None:
        return self._store.get(id)

    async def list(self, *, limit: int, cursor: <Feature>Id | None) -> list[<Feature>]:
        items = sorted(self._store.values(), key=lambda e: e.created_at, reverse=True)
        return items[:limit]

    async def add(self, data: Create<Feature>Input) -> <Feature>:
        raise NotImplementedError  # construct + persist; assign id

    async def save(self, entity: <Feature>) -> <Feature>:
        self._store[entity.id] = entity
        return entity

    async def delete(self, id: <Feature>Id) -> None:
        self._store.pop(id, None)
```

**Checklist**:
- [ ] The service depends on the `Protocol`, never on a concrete adapter or the DB driver.
- [ ] Parameterized queries only in the SQL adapter — never string-built SQL.
- [ ] Every query is scoped to its tenant/owner where multi-tenant; no cross-tenant reads.
- [ ] An in-memory adapter exists so the service is testable without a database.
- [ ] (sync projects: drop `async`/`await` consistently across this and the service.)

### Phase 4 — Service (pure orchestration, `Result`-returning)

**Goal**: The use cases. Dependencies injected; expected failures returned as a typed `Result`, not raised.

**Generate**: `<pkg>/<feature>/service.py`

```python
"""Application services for <feature>.

Pure orchestration: dependencies (repository, clock, id factory) are injected.
Expected failures are returned as a typed Result so callers must handle them.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Generic, TypeVar

from .contracts import Create<Feature>Input
from .models import <Feature>, <Feature>Id
from .repository import <Feature>Repository

T = TypeVar("T")
E = TypeVar("E", bound=Enum)


class <Feature>Error(Enum):
    """Expected, typed failure modes a caller can switch on."""

    NOT_FOUND = "not_found"
    CONFLICT = "conflict"
    INVALID_STATE = "invalid_state"


@dataclass(frozen=True, slots=True)
class Ok(Generic[T]):
    value: T


@dataclass(frozen=True, slots=True)
class Err(Generic[E]):
    error: E
    message: str = ""


Result = Ok[T] | Err[E]


@dataclass(frozen=True, slots=True)
class <Feature>Service:
    """Use cases for <feature>. Construct once with its dependencies."""

    repo: <Feature>Repository
    now: Callable[[], datetime]          # injected clock — never datetime.now() inline
    new_id: Callable[[], <Feature>Id]    # injected id factory — never uuid4() inline

    async def create(
        self, data: Create<Feature>Input
    ) -> Result[<Feature>, <Feature>Error]:
        # Guard clauses first; happy path last.
        entity = await self.repo.add(data)
        return Ok(entity)

    async def get(
        self, id: <Feature>Id
    ) -> Result[<Feature>, <Feature>Error]:
        entity = await self.repo.get(id)
        if entity is None:
            return Err(<Feature>Error.NOT_FOUND)
        return Ok(entity)

    async def archive(
        self, id: <Feature>Id
    ) -> Result[<Feature>, <Feature>Error]:
        entity = await self.repo.get(id)
        if entity is None:
            return Err(<Feature>Error.NOT_FOUND)
        saved = await self.repo.save(entity.archived(now=self.now()))
        return Ok(saved)
```

**Checklist**:
- [ ] Zero direct I/O construction — repo, clock (`now`), and id factory (`new_id`) are injected.
- [ ] Expected failures returned as `Err(...)`; exceptions reserved for the unexpected.
- [ ] Every branch is unit-testable without mocks (inject a fake clock and the in-memory repo).
- [ ] No `datetime.now()` / `uuid4()` / `random` called directly inside a use case.

### Phase 5 — Interface Surface

Generate **one** of the following based on `--surface` / detection.

**`api` (FastAPI shown; adapt for Flask/Litestar/Django)** → `<pkg>/<feature>/router.py`:

```python
"""HTTP surface for <feature>. Thin: parse → call service → map Result → response."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from .contracts import <Feature>DTO, Create<Feature>Input
from .models import <Feature>Id
from .service import Err, <Feature>Error, <Feature>Service

router = APIRouter(prefix="/<feature>s", tags=["<feature>"])


def get_service() -> <Feature>Service:  # wired in composition root / DI container
    raise NotImplementedError


_STATUS = {
    <Feature>Error.NOT_FOUND: status.HTTP_404_NOT_FOUND,
    <Feature>Error.CONFLICT: status.HTTP_409_CONFLICT,
    <Feature>Error.INVALID_STATE: status.HTTP_422_UNPROCESSABLE_ENTITY,
}


@router.post("", response_model=<Feature>DTO, status_code=status.HTTP_201_CREATED)
async def create_<feature>(
    body: Create<Feature>Input,  # FastAPI parses+validates at the boundary
    service: <Feature>Service = Depends(get_service),
) -> <Feature>DTO:
    result = await service.create(body)
    if isinstance(result, Err):
        raise HTTPException(status_code=_STATUS[result.error], detail=result.message or result.error.value)
    e = result.value
    return <Feature>DTO(id=e.id, name=e.name, status=e.status, created_at=e.created_at, updated_at=e.updated_at)
```

**`cli` (Typer shown)** → `<pkg>/<feature>/cli.py`:

```python
"""CLI surface for <feature>. Parse args → call service → render Result → exit code."""

from __future__ import annotations

import typer

app = typer.Typer(help="Manage <feature>s")


@app.command()
def create(name: str = typer.Option(..., help="<Feature> name")) -> None:
    """Create a <feature>. Exits non-zero on an expected failure."""
    # build input model, call service, print DTO or error, raise typer.Exit(code) on Err
    raise NotImplementedError
```

**`lib`** → ensure `<pkg>/<feature>/__init__.py` re-exports the public surface only (`Create<Feature>Input`, `<Feature>DTO`, `<Feature>Service`, error type) and nothing internal.

**`worker`** → `<pkg>/<feature>/tasks.py`: an idempotent task handler that parses the message into `Create<Feature>Input`, calls the service, and handles retries/dead-letter explicitly.

**Checklist**:
- [ ] The surface is thin: parse → authorize (if applicable) → call service → map `Result` → response/exit.
- [ ] Input parsed/validated at the boundary; output is the DTO, never the raw domain or persistence model.
- [ ] Errors mapped to proper status codes / exit codes — never a blanket `500`/`1`; internals never leaked.
- [ ] `api`: authorization re-checked here for protected operations, not assumed from a gateway.

### Phase 6 — Wiring & Side Effects

**Goal**: A composition root constructs the concrete dependencies (real repo, real clock, real id factory) and supplies them. Slow/unreliable side effects run outside the request path.

- Wire `get_service()` / the CLI entry to build `<Feature>Service(repo=..., now=datetime.now, new_id=lambda: <Feature>Id(str(uuid4())))`.
- Offload emails, webhooks, and third-party calls to a task/queue; keep them idempotent. Set timeouts on every outbound call.
- Register new env/config in the typed settings model — never read `os.environ` ad-hoc.

### Phase 7 — Tests (skip if `--skip-tests`)

**Goal**: Confidence without brittleness. Pure unit tests with no mocks; integration tests at real boundaries.

**Generate**: `tests/<feature>/test_service.py`

```python
"""Unit tests for <Feature>Service — pure, no mocks, deterministic."""

from __future__ import annotations

from datetime import datetime, timezone

import pytest

from <pkg>.<feature>.contracts import Create<Feature>Input
from <pkg>.<feature>.repository import InMemory<Feature>Repository
from <pkg>.<feature>.service import Err, Ok, <Feature>Error, <Feature>Service

FIXED_NOW = datetime(2026, 1, 1, tzinfo=timezone.utc)


def make_service() -> <Feature>Service:
    counter = {"n": 0}

    def new_id() -> str:  # deterministic id factory for tests
        counter["n"] += 1
        return f"<feature>-{counter['n']:04d}"

    return <Feature>Service(
        repo=InMemory<Feature>Repository(),
        now=lambda: FIXED_NOW,
        new_id=new_id,  # type: ignore[arg-type]  # branded NewType in real code
    )


@pytest.mark.asyncio
async def test_get_missing_returns_not_found() -> None:
    service = make_service()
    result = await service.get("missing")  # type: ignore[arg-type]
    assert isinstance(result, Err)
    assert result.error is <Feature>Error.NOT_FOUND


@pytest.mark.asyncio
async def test_create_then_get_round_trips() -> None:
    service = make_service()
    created = await service.create(Create<Feature>Input(name="example"))
    assert isinstance(created, Ok)
```

Also generate `tests/<feature>/test_contracts.py` (boundary validation: rejects empty/oversized/extra fields) and, for `api`/`worker`, an integration test hitting the real surface with an ephemeral store.

**Checklist**:
- [ ] Service tests use the in-memory repo + injected clock/id factory — zero mocks.
- [ ] Boundary tests assert that invalid input is rejected (length, type, extra keys).
- [ ] Tests are deterministic (frozen time, seeded ids) and fast.
- [ ] A regression test exists for every bug the clarification surfaced.

### Phase 8 — Ship Checklist

```
[ ] ruff format --check  &&  ruff check            → clean
[ ] mypy --strict <pkg>/<feature> tests/<feature>  → clean
[ ] pytest tests/<feature>                          → green
[ ] Public API re-exported intentionally; internals not leaked
[ ] New config registered in the typed settings model; secrets via secret manager
[ ] Errors mapped to correct status/exit codes; no internals leaked to callers
[ ] CHANGELOG updated; ADR recorded if an architectural decision was made (/speckit-decision-new)
[ ] uv.lock updated if dependencies changed
```

---

## Post-Scaffold Verification

After generating files, verify and report:

1. No `Any` in any generated signature; no bare `# type: ignore`.
2. No direct `datetime.now()` / `uuid4()` / `random` / DB driver import inside `service.py`.
3. No string-built SQL or `shell=True`; boundary models reject unknown keys.
4. The surface returns DTOs, never the domain or persistence model.
5. All imports resolve and the slice type-checks: `mypy --strict`.

Print the scaffold summary:

```
## Feature scaffold complete

**Feature**: <feature>  **Surface**: <surface>  **I/O**: <async|sync>

**Files created**:
  <pkg>/<feature>/contracts.py     ← boundary models (parse-don't-validate)
  <pkg>/<feature>/models.py        ← domain model (branded ids, pure transitions)
  <pkg>/<feature>/repository.py    ← Protocol + in-memory adapter
  <pkg>/<feature>/service.py       ← pure services (Result, injected deps)
  <pkg>/<feature>/<router|cli|tasks>.py  ← interface surface
  tests/<feature>/test_service.py
  tests/<feature>/test_contracts.py

**Verify**:
  ruff check && mypy --strict <pkg>/<feature> && pytest tests/<feature>

**Next steps**:
  - /speckit-plan <feature>        for a full implementation plan
  - /speckit-scaffold-module       to add another typed module
  - /speckit-decision-new <decision>    to record an architectural decision
  - /speckit-audit                 to verify constitution compliance
```

## Post-Execution Hooks

Check `.specify/extensions.yml` for `hooks.after_feature`. Apply standard hook-processing.

---

## Knowledge base

The project constitution at `.specify/memory/constitution.md` is authoritative. For deep,
task-specific guidance (directives + Do/Don't code patterns), load only the
relevant reference file from the installed knowledge base — do not read them all:

- **type safety** → `.specify/memory/knowledge/type-safety.md`
- **data & boundaries** → `.specify/memory/knowledge/data-and-boundaries.md`
- **architecture** → `.specify/memory/knowledge/architecture.md`
- **error handling** → `.specify/memory/knowledge/error-handling.md`
- **testing** → `.specify/memory/knowledge/testing.md`
- **security** → `.specify/memory/knowledge/security.md`
- **principles** → `.specify/memory/knowledge/principles.md`
- **design patterns** → `.specify/memory/knowledge/design-patterns.md`
