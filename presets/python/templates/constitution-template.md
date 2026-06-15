# [PROJECT_NAME] Constitution
<!-- A Python project governed by Spec-Driven Development. Stack-agnostic: web service, CLI, library, data pipeline, or automation — the directives below hold regardless. -->

This constitution governs **behavior**, not technology choices. The team chooses concrete tools in the plan phase; the directives below hold regardless of whether the project is a web API, a CLI, a library on PyPI, a data pipeline, or an automation script, and regardless of which framework, ORM, or runtime is selected.

Every directive carries two tags, and the Python Engineering section adds a third:

- **Phase** — when the behavior must hold.
- **Criticality** — how strictly it is enforced.
- **Scope** *(Python Engineering only)* — where the behavior applies: `App` (application code), `Lib` (reusable/published code), or `Both`.

The non-negotiable toolchain baseline is **uv** (environments + locking), **Ruff** (lint + format), **mypy `--strict`** (static typing), and **pytest** (tests). Directives reference these by capability, not as incidental preferences.

---

## Operating Framework

### Phases

| Phase | Meaning |
|---|---|
| **P1 — Foundation** | Must hold before the first feature is written. Skipping P1 is a refactor with compounding interest. |
| **P2 — MVP** | Must hold before the first real user or downstream consumer touches the code. |
| **P3 — Hardening** | Must hold before the first production deployment or first published release. |
| **P4 — Scale** | Continuous practice for a live, evolving system. |

### Criticality

| Level | Meaning |
|---|---|
| **Critical** | Violations block release. No exceptions without a recorded waiver and a fixed expiry. |
| **High** | Violations require an explicit, time-bound exception approved at review. |
| **Medium** | Default expectation; deviations are noted and tracked. |
| **Low** | Recommended; revisit during regular audits. |

---

## Core Principles

### I. Type-Safety Without Escape Hatches (Critical)
The whole project type-checks under **mypy `--strict`** (or an equivalently strict pyright config). `Any`, bare `# type: ignore`, and `cast()` used to silence the checker are violations, not stylistic choices. Untrusted input (HTTP, CLI args, environment, files, the network, third-party payloads) is **parsed into a typed model at the boundary** before any business logic sees it. The type checker is the first test suite.

### II. Explicit Boundaries, Validated Inputs (Critical)
Every public function, every process boundary, and every I/O edge has a precise, declared contract. Inputs are parsed and narrowed at the boundary; downstream code receives validated, typed values only — never raw `dict[str, Any]`, never unparsed strings. "It worked in the REPL" is not a contract.

### III. Pure Core, Imperative Shell (Critical)
Business logic lives in pure, deterministic functions that take their dependencies as arguments. Side effects — I/O, clocks, randomness, network, global state — are pushed to the edges and injected, never reached for in the middle of a computation. This is what makes the core unit-testable without mocks.

### IV. Errors Are Typed and Intentional (High)
Expected failure is modeled in the type system (a typed `Result`, a sentinel, or a narrow exception hierarchy) and handled at a deliberate boundary. Exceptions are for the genuinely exceptional. Bare `except:` and `except Exception: pass` are violations. Errors carry context internally and never leak internals (stack traces, secrets, SQL) to untrusted callers.

### V. Determinism and Reproducibility (High)
The environment is reproducible from a committed lockfile (`uv.lock`) and a pinned interpreter version. The same inputs produce the same outputs: no reliance on dict ordering for correctness, no hidden global mutable state, no unseeded randomness in logic that must be testable. CI installs from the lockfile, not from floating ranges.

### VI. Tests Are Part of the Design (High)
Code is written to be tested: pure functions for logic, injected effects at the edges. The test suite runs under **pytest**, is deterministic, and is fast enough to run on every change. Coverage is a signal, not a target gamed with assertion-free tests. A bug fixed without a regression test is a bug deferred.

### VII. Security by Default (Critical)
Secrets never live in the repo, in source, in logs, or in tracebacks. All external input is hostile until parsed. No `eval`/`exec` on untrusted data, no `subprocess(..., shell=True)` with interpolated input, no string-built SQL, no insecure deserialization (`pickle`/`yaml.load`) of untrusted bytes. Dependencies are pinned and vulnerability-scanned.

### VIII. Quality Code Is the Default (High)
Ruff (lint + format), mypy, and pytest run in CI on every change; warnings on protected branches are errors. Modules have one reason to change; public APIs are named precisely, fully typed, and documented with docstrings. Abstractions earn their cost — clarity beats cleverness every time.

---

## Type Safety & Static Analysis Behaviors

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | Run `mypy --strict` (or pyright `strict`) over the whole package; type errors fail CI. |
| P1 | Critical | Ban `Any` in public signatures; use precise types, `object` + narrowing, or a `Protocol`. |
| P1 | Critical | Annotate every function — parameters and return — including `-> None`; no implicitly-typed public API. |
| P1 | High | Ban bare `# type: ignore`; require `# type: ignore[code]  # reason` with the specific error code and a justification. |
| P1 | High | Enable `warn_unused_ignores`, `warn_redundant_casts`, `disallow_untyped_defs`, `no_implicit_optional`. |
| P2 | High | Reserve `cast()` for genuinely un-expressible narrowing; never use it to paper over a real type error. |
| P2 | High | Use `typing.TYPE_CHECKING` + `from __future__ import annotations` to avoid import cycles and runtime cost from typing-only imports. |
| P2 | High | Use `Protocol` (structural typing) for dependency seams; depend on the narrowest protocol a consumer needs. |
| P2 | Medium | Prefer `typing.NewType` / branded aliases for IDs and tokens (`UserId = NewType("UserId", str)`) over raw `str`. |
| P2 | Medium | Use `Literal`, `Enum`, and `assert_never` to make illegal states unrepresentable and switches exhaustive. |
| P3 | Medium | Ship `py.typed` for any installed/published package so downstream consumers get the types. |
| P3 | Medium | Keep `mypy` clean on the test suite too — tests are code and catch contract drift. |

---

## Code Quality & Style Behaviors

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | One linter, one formatter: **Ruff** for both. Format-on-save and `ruff check`/`ruff format --check` in CI; no second formatter. |
| P1 | High | Enable a strong Ruff rule set (`E,F,I,UP,B,SIM,RUF,ANN,PTH,TID`, etc.); fix or explicitly `# noqa: CODE  # reason` — never blanket-disable. |
| P1 | High | Follow PEP 8 / PEP 257; `snake_case` functions and variables, `PascalCase` classes, `SCREAMING_SNAKE_CASE` constants, `_private` by underscore convention. |
| P2 | High | One module, class, or function has one reason to change (SRP). Keep functions short with a single level of abstraction; keep cyclomatic complexity low. |
| P2 | High | Early returns over nested `if`/`else` pyramids. Guard clauses on top, happy path at the bottom. |
| P2 | High | Self-documenting names; no single-letter names outside tight comprehensions; no abbreviations that aren't domain-standard. |
| P2 | Medium | Boolean parameters are a smell — prefer an `Enum` or split the function. Limit positional args; group related ones into a dataclass/typed options object; use keyword-only args (`*`) for clarity. |
| P2 | Medium | DRY only after the third repetition (Rule of Three); avoid premature abstraction. KISS / YAGNI. |
| P2 | Medium | Public modules, classes, and functions carry docstrings explaining the *why* and the contract, not the obvious *what*. |
| P3 | Medium | No dead code, no commented-out blocks, no `print` debugging left in; use the logger. Ban wildcard imports. |
| P3 | Low | Prefer `pathlib.Path` over `os.path`; f-strings over `%`/`.format`; comprehensions over `map`/`filter` where clearer. |

---

## Architecture & Design Behaviors

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | **Pure core, imperative shell**: business logic is side-effect-free and dependency-injected; I/O lives at the edges. |
| P1 | High | **DIP** — high-level logic depends on abstractions (`Protocol`/ABC), not concrete implementations. Inject the DB, clock, RNG, HTTP client, and logger; never instantiate them inside business logic. |
| P1 | High | **SRP / OCP** — one reason to change; extend via new functions/strategies, not by editing stable ones. |
| P2 | High | Define domain types (dataclasses / Pydantic / attrs) distinct from persistence rows and from wire/DTO shapes; map between layers explicitly. |
| P2 | High | **Composition over inheritance**; deep class hierarchies are a smell. Use small functions and protocols before reaching for a base class. |
| P2 | High | **ISP / LSP** — split fat interfaces into role-specific protocols; subtypes honor the parent contract (no surprise raises, no narrower inputs, no broader outputs). |
| P2 | Medium | Keep modules acyclic; ban circular imports (lint rule / import-linter). At most one public `__init__.py` re-export boundary per package; don't hide cycles behind barrels. |
| P3 | Medium | Keep functions referentially transparent where feasible; mutation is opt-in, not the default. Prefer immutable dataclasses (`frozen=True`) and tuples for value objects. |

---

## Data, Validation & Boundary Behaviors

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | **Parse, don't validate** — convert untrusted input into a typed model at the boundary, then trust the type. Downstream code never sees raw `dict`/`str`. |
| P2 | Critical | Validate every external input — HTTP body, query/path params, CLI args, env vars, file contents, queue messages, third-party responses — with a schema (Pydantic/`dataclasses`+validators/`attrs`). |
| P2 | Critical | Validate configuration and environment at startup with a typed settings model; fail fast and loudly on missing or malformed values. Never read `os.environ[...]` ad-hoc deep in the code. |
| P2 | High | Define DTOs that decouple internal domain models from API/wire shapes; never serialize a persistence model straight to the client. |
| P2 | High | Never trust runtime types across a process boundary — types are erased; the schema is the contract. |
| P3 | High | Generate types/schemas from the single source of truth (DB schema, OpenAPI, protobuf) — never hand-sync parallel definitions. |
| P3 | Medium | Return `Result[T, E]`-style values (or a narrow exception type) for *expected* failures; reserve exceptions for the unexpected. |

---

## Error Handling & Resilience Behaviors

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | Ban bare `except:` and silent `except Exception: pass`; catch the narrowest exception and handle it deliberately. |
| P2 | High | Model domain errors as a small, typed exception hierarchy or a `Result` union — not generic `Exception("...")` strings the caller must parse. |
| P2 | High | Preserve causality with `raise NewError(...) from err`; never swallow the original traceback. |
| P2 | High | Catch exceptions where you can do something about them, not everywhere; let unexpected errors surface to a single top-level boundary that logs and returns a safe response. |
| P2 | Medium | Use `contextlib`/context managers (or `try/finally`) so resources (files, sockets, locks, sessions) are always released, including on error. |
| P3 | High | Make external interactions resilient: explicit timeouts on every network/DB call, bounded retries with backoff for idempotent operations, and a circuit-breaker or fail-fast for hard-down dependencies. |
| P3 | Medium | Make operations idempotent where feasible so retries are safe; guard non-idempotent side effects with idempotency keys. |

---

## Concurrency & Async Behaviors

| Phase | Crit. | Behavior |
|---|---|---|
| P2 | Critical | Don't block the event loop: never call sync/blocking I/O inside `async def`; offload CPU-bound or blocking work to a thread/process pool (`asyncio.to_thread`, executors). |
| P2 | High | Don't mix paradigms incoherently: pick async or sync per boundary; don't call `asyncio.run` inside a running loop or sprinkle `loop.run_until_complete`. |
| P2 | High | Await or explicitly manage every coroutine and task; never create fire-and-forget tasks without holding a reference and handling their exceptions. |
| P3 | High | Protect shared mutable state with the right primitive (`asyncio.Lock`, `threading.Lock`, queues); prefer message passing and immutable data over shared state. |
| P3 | Medium | Treat the GIL as real: use `multiprocessing`/subprocess or native extensions for CPU-bound parallelism; threads for I/O-bound concurrency. |
| P3 | Medium | Bound concurrency (semaphores, pool sizes, connection-pool limits) so the system degrades gracefully under load rather than exhausting resources. |

---

## Security Behaviors

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | Secrets live in a secret manager or untracked env, never in the repo, source, build args, logs, or tracebacks. Scan history and CI for leaked credentials. |
| P1 | Critical | Treat all external input as hostile until parsed and narrowed at the boundary. |
| P2 | Critical | No `eval`/`exec`/`compile` on untrusted input. No `subprocess(..., shell=True)` with interpolated values — pass an argument list and avoid the shell. |
| P2 | Critical | Parameterized queries everywhere; never build SQL by string concatenation or f-string interpolation of user data. |
| P2 | Critical | No insecure deserialization of untrusted bytes: no `pickle.loads`, no `yaml.load` (use `yaml.safe_load`), no `marshal` on external data. |
| P2 | Critical | Hash passwords with a memory-hard algorithm (argon2 / bcrypt / scrypt); never store, log, or echo them. Use `secrets` (not `random`) for tokens. |
| P2 | High | Validate and constrain file paths from untrusted input (resolve + confine to a base dir); reject traversal. Treat uploads as hostile — check type and size, store outside executable roots. |
| P2 | High | Set explicit timeouts and verify TLS on every outbound request; never disable certificate verification. |
| P3 | Critical | Apply least privilege to DB roles, API keys, file permissions, and service accounts — scoped to what they need and nothing more. |
| P3 | High | Pin dependencies and vulnerability-scan every change (`pip-audit`/`uv` + advisory DB); patch CVEs in libraries and the interpreter promptly. |
| P3 | High | Log auth events, permission changes, and admin actions to an append-only audit trail; never log secrets, tokens, or full PII. |

---

## Performance Behaviors

| Phase | Crit. | Behavior |
|---|---|---|
| P2 | High | Measure before optimizing: profile (`cProfile`/`py-spy`/`scalene`) to find the real hot path; never guess. |
| P2 | High | Choose the right data structure: `set`/`dict` for membership and lookup, generators for large/streamed sequences, `deque` for queues. Don't build a list to immediately iterate once. |
| P2 | Medium | Avoid accidental O(n²): no repeated `in list` on large data, no string concatenation in loops (use `"".join`), no rebuilding immutable structures in a loop. |
| P3 | High | Set explicit timeouts and right-size connection/thread pools; batch and paginate I/O; avoid N+1 query patterns. |
| P3 | Medium | Stream large datasets rather than loading them whole; bound memory with chunking and generators. |
| P3 | Medium | Cache deliberately and explicitly (e.g. `functools.lru_cache` for pure functions, an external cache for shared state) with a clear invalidation story — never an implicit, unbounded cache. |
| P4 | Medium | Track performance budgets (latency P95, throughput, memory) in CI or monitoring; alert on regressions rather than discovering them in production. |

---

## Testing Behaviors

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | Tests run under **pytest** and pass deterministically in CI on every change; a red suite blocks merge. |
| P2 | Critical | Unit-test the pure core with zero mocks (pure functions + injected effects make this possible). Cover happy path, boundaries, and the documented error paths. |
| P2 | High | Test behavior and contracts, not implementation details; avoid asserting on private internals that refactors legitimately change. |
| P2 | High | Make tests deterministic: inject the clock and RNG, freeze time, seed randomness; no reliance on network, wall-clock, or test ordering. |
| P2 | Medium | Use fixtures for setup and parametrization for input matrices; keep each test focused on one behavior with a clear arrange/act/assert shape. |
| P3 | High | Add integration tests at real boundaries (DB, HTTP, filesystem) using ephemeral resources (tmp dirs, testcontainers, in-memory or throwaway DBs) — never a shared mutable test environment. |
| P3 | Medium | Property-based tests (Hypothesis) for parsers, serializers, and invariant-heavy logic; a fixed regression test for every fixed bug. |
| P3 | Medium | Coverage does not regress against the baseline; new code ships with tests. Coverage measures reach, not quality — don't game it. |

---

## Packaging, Tooling & Dependency Behaviors

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | Single source of project metadata: `pyproject.toml` (PEP 621). No `setup.py`/`setup.cfg` duplication; one build backend. |
| P1 | Critical | Reproducible environments via **uv**: `uv.lock` committed, interpreter version pinned (`.python-version`/`requires-python`), CI installs from the lock with `uv sync --frozen`. |
| P1 | High | Pin direct dependencies with sensible bounds; keep dev/test/docs dependencies in dependency groups, not in the runtime set. |
| P2 | High | Configure Ruff, mypy, and pytest in `pyproject.toml` (or dedicated configs) and run all three in CI; the same commands run locally and in CI. |
| P2 | High | Support the interpreter versions you claim to (test the matrix); don't use features newer than `requires-python` allows. |
| P3 | High | For published packages: semantic versioning, a `CHANGELOG`, `py.typed`, a tested build (`uv build`), and a verified artifact before publish (Trusted Publishing / no tokens in CI logs). |
| P3 | Medium | Audit dependencies on a cadence; remove unused ones; prefer the standard library when it suffices over adding a dependency. |

---

## Observability & Operations Behaviors

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | High | Use the `logging` module (or structured logger like `structlog`), never `print`, for diagnostics. Configure logging at the application entry point; libraries log to a `NullHandler` and never configure global logging. |
| P2 | High | Logs are structured (event, context, outcome) and carry a correlation/request ID across boundaries; errors include context for debugging and nothing sensitive. |
| P2 | High | CI runs format-check, lint, typecheck, and tests on every PR; failures block merge. Builds are reproducible from the lockfile. |
| P3 | High | Emit metrics and traces (OpenTelemetry where applicable) to a central stack; alert on real signal — error rate, latency, saturation — not noise. |
| P3 | High | Deploy immutable, versioned artifacts traceable to a commit; database/schema migrations are reviewed, reversible, and applied through one pipeline — never by hand in production. |
| P3 | Medium | Health checks gate rollouts; document and rehearse the rollback path. Back up stateful data and test restores on a cadence. |
| P4 | Medium | Incident retrospectives are blameless, written, and produce dated action items with owners. Review cost and capacity against real usage. |

---

## Quality Gates

A change reaches `main` only when **all** of the following hold for the phase the project is in:

- All **Critical** directives for the current phase and every prior phase are satisfied — or covered by a recorded, time-bound waiver.
- All **High** directives are satisfied or carry an approved exception with a fix date.
- `ruff format --check`, `ruff check`, `mypy --strict`, and `pytest` pass in CI; coverage does not regress against the baseline.
- Security review has approved any change touching authentication, authorization, deserialization, subprocess/shell, SQL, file-path handling, or secret management.
- The environment installs reproducibly from `uv.lock` on a clean machine.

A change reaches **production** (or a **published release**) only when the artifact is immutable, versioned, traceable to a commit, observable, and reversible.

---

## Governance

This constitution supersedes ad-hoc conventions. When a directive here conflicts with a tutorial, a blog post, a library changelog, or an LLM suggestion, **this document wins** until it is formally amended.

- **Amendments** require a PR that updates this file, a changelog entry, and — when a directive changes criticality or phase — a migration plan for code already in the affected category. Significant architectural decisions are also recorded as ADRs under `docs/adr/`.
- **Waivers** for Critical or High directives must be recorded inline in the affected code with an owner, a reason, and an expiry date no further than one release cadence away (and/or in `.specify/waivers.yml`).
- **Reviews** must verify compliance explicitly: every PR description references the directives it touches; every reviewer checks them.
- **Drift audits** run on a scheduled cadence (at minimum once per release) via `/speckit.audit` and `/speckit.decision.audit` to detect silent regressions against this constitution and the accepted ADRs.

The runtime companion for day-to-day agent guidance lives at `templates/agent-context.md` and is mirrored into the project's agent context file (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, or equivalent).

**Version**: [CONSTITUTION_VERSION] | **Ratified**: [RATIFICATION_DATE] | **Last Amended**: [LAST_AMENDED_DATE]
