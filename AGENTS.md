# Python Project — Agent Operating Rules

These rules apply on **every turn**. They are derived from the project constitution at `.specify/memory/constitution.md`; that document is the source of truth and supersedes anything here on conflict.

A directive's weight depends on its **Phase** (when it must hold) and **Criticality** (how strictly).

- Phases: **P1 Foundation** → **P2 MVP** → **P3 Hardening** → **P4 Scale** (continuous).
- Criticality: **Critical** (blocks release) · **High** (needs an approved, time-bound exception) · **Medium** (default expectation) · **Low** (recommended).

Toolchain baseline (non-negotiable): **uv** · **Ruff** (lint + format) · **mypy `--strict`** · **pytest**. Before proposing code, check the relevant section below. When a directive conflicts with a request, surface the conflict — don't silently violate it.

---

## Universal rules (always)

- **Type safety is a contract.** Everything type-checks under `mypy --strict`. No `Any` in public signatures. No bare `# type: ignore` (use `# type: ignore[code]  # reason`). No `cast()` to silence a real error. Annotate every function fully, including `-> None`.
- **Parse, don't validate.** Convert untrusted input (HTTP, CLI, env, files, network, third-party) into a typed model at the boundary, then trust the type. Downstream code never sees raw `dict[str, Any]` or unparsed strings.
- **Pure core, imperative shell.** Business logic is pure and takes its dependencies (DB, clock, RNG, HTTP client, logger) as arguments. Side effects live at the edges. This is what makes the core testable without mocks.
- **Errors are typed and intentional.** Model expected failure in the types (a `Result`, a sentinel, or a narrow exception hierarchy). Catch the narrowest exception. Never `except:` or `except Exception: pass`. Preserve the cause with `raise ... from err`.
- **Security by default.** Secrets never in repo, source, logs, or tracebacks. No `eval`/`exec` on untrusted input, no `shell=True` with interpolation, no string-built SQL, no `pickle`/`yaml.load` of untrusted bytes. `secrets` for tokens, not `random`.
- **Reproducible.** Environment comes from a committed `uv.lock` and a pinned interpreter. CI installs `--frozen`. Logic is deterministic — inject the clock and seed the RNG.
- **Tests are part of the design.** Code is written to be tested; a bug fixed without a regression test is a bug deferred.

---

## Type system & static analysis — what to do

- Run `mypy --strict` (or pyright `strict`) over the package **and the tests**; type errors fail CI.
- Use precise types. For untrusted/dynamic data use `object` and narrow, or a `Protocol` — never `Any`.
- `from __future__ import annotations` + `if TYPE_CHECKING:` for typing-only imports and to break cycles.
- `Protocol` (structural typing) for dependency seams; depend on the narrowest protocol a consumer needs.
- `NewType`/branded aliases for IDs and tokens (`UserId = NewType("UserId", str)`) — not raw `str`.
- `Literal`, `Enum`, and `typing.assert_never` to make illegal states unrepresentable and `match`/`if` chains exhaustive.
- Ship `py.typed` for any installed/published package.

## Type system & static analysis — what NOT to do

- No `Any` in public signatures. No `dict[str, Any]` as a domain type — define a model.
- No bare `# type: ignore`, no `cast()` to hide a genuine error, no implicitly-typed public functions.
- No raw `str`/`int` for IDs, emails, money, or tokens where a `NewType` or value object expresses intent.

---

## Code quality & style — what to do

- One formatter, one linter: **Ruff**. `ruff format --check` and `ruff check` in CI. Format on save.
- PEP 8 / PEP 257 naming: `snake_case` functions/vars, `PascalCase` classes, `SCREAMING_SNAKE_CASE` constants.
- Small functions, single level of abstraction, low complexity. Guard clauses on top; happy path at the bottom. Early returns over nested `if`/`else`.
- Self-documenting names. Keyword-only args (`*`) for clarity; group related parameters into a dataclass. Public API carries docstrings explaining the *why* and the contract.
- `pathlib.Path` over `os.path`; f-strings; comprehensions where clearer; `"".join(...)` over `+` in loops.

## Code quality & style — what NOT to do

- No wildcard imports, no commented-out code, no leftover `print` debugging (use the logger).
- No boolean-parameter explosions — use an `Enum` or split the function.
- No premature abstraction — refactor on the third repetition (Rule of Three), not the second.
- No blanket `# noqa` — use `# noqa: CODE  # reason` for the specific rule, or fix it.

---

## Architecture & design — what to do

- **Pure core, imperative shell.** Inject the DB, clock, RNG, HTTP client, and logger; never instantiate them inside business logic.
- Depend on abstractions (`Protocol`/ABC), not concretions (DIP). Split fat interfaces into small role-specific protocols (ISP).
- Keep domain types separate from persistence rows and from wire/DTO shapes; map between layers explicitly.
- Composition over inheritance. Prefer immutable dataclasses (`frozen=True`) and tuples for value objects.
- One reason to change per module (SRP); extend via new code, not by editing stable code (OCP).

## Architecture & design — what NOT to do

- Don't reach for I/O, the clock, the network, or global state in the middle of a computation.
- Don't serialize a persistence model straight to a client — return a DTO.
- Don't build deep class hierarchies; don't create circular imports; don't hide cycles behind `__init__` barrels.

---

## Data, validation & boundaries — what to do

- Validate every external input — HTTP body, params, CLI args, env, file contents, queue messages, third-party responses — with a schema (Pydantic / dataclass+validators / attrs) at the boundary.
- Validate config/environment at startup with a typed settings model; fail fast on missing or malformed values.
- Define DTOs decoupling internal models from wire shapes. Generate types from the single source of truth (DB schema, OpenAPI) — never hand-sync.
- `Result[T, E]` or a narrow exception for *expected* failures; exceptions for the unexpected.

## Data, validation & boundaries — what NOT to do

- Don't pass raw `dict`/`str` from the boundary into business logic.
- Don't read `os.environ[...]` ad-hoc deep in the code — go through the settings model.
- Don't trust runtime types across a process boundary — the schema is the contract.

---

## Error handling & resilience — what to do

- Catch the narrowest exception you can act on; let unexpected errors reach a single top-level boundary that logs and returns a safe response.
- Model domain errors as a small typed hierarchy or a `Result` union. Preserve causality with `raise NewError(...) from err`.
- Context managers / `try/finally` so resources are always released.
- Explicit timeouts on every network/DB call; bounded retries with backoff for idempotent operations; make operations idempotent where feasible.

## Error handling & resilience — what NOT to do

- No bare `except:`. No `except Exception: pass`. No swallowing the original traceback.
- No catch-everything-everywhere — handle errors where you can do something about them.
- No unbounded retries, no network/DB calls without a timeout.

---

## Concurrency & async — what to do

- Keep the event loop unblocked: offload blocking/CPU-bound work via `asyncio.to_thread` or an executor.
- Hold a reference to every task and handle its exceptions; await what you start.
- Protect shared mutable state with the right lock/queue; prefer message passing and immutable data.
- Threads for I/O-bound, processes for CPU-bound (the GIL is real). Bound concurrency with semaphores and pool limits.

## Concurrency & async — what NOT to do

- Don't call blocking/sync I/O inside `async def`. Don't `asyncio.run` inside a running loop.
- Don't create fire-and-forget tasks with no reference and no error handling.
- Don't share mutable state across threads/tasks without synchronization.

---

## Security — what to do

- Secrets in a secret manager or untracked env — never in repo, source, build args, logs, or tracebacks.
- Treat all external input as hostile until parsed. Parameterized queries only. `subprocess` with an argument list, not `shell=True`.
- `yaml.safe_load`, never `pickle.loads` on untrusted bytes. No `eval`/`exec`/`compile` on untrusted input.
- Hash passwords with argon2/bcrypt/scrypt; `secrets` for tokens. Confine untrusted file paths to a base dir; reject traversal.
- Explicit timeouts and TLS verification on every outbound request. Least privilege on DB roles, keys, and file permissions.
- Pin and vulnerability-scan dependencies (`pip-audit`); patch CVEs promptly.

## Security — what NOT to do

- Never interpolate user data into SQL, shell commands, or `eval`.
- Never `pickle.loads` / `yaml.load` untrusted bytes. Never disable TLS verification.
- Never log secrets, tokens, or full PII. Never use `random` for security tokens.

---

## Testing — what to do

- pytest, deterministic, fast, green in CI on every change. Unit-test the pure core with zero mocks.
- Inject the clock and RNG; freeze time; seed randomness. Cover happy path, boundaries, and documented error paths.
- Fixtures for setup, parametrization for input matrices; integration tests at real boundaries with ephemeral resources.
- A regression test for every fixed bug; property-based tests (Hypothesis) for parsers and invariant-heavy logic.

## Testing — what NOT to do

- Don't test private internals that refactors legitimately change — test behavior and contracts.
- Don't depend on network, wall-clock, or test ordering. Don't game coverage with assertion-free tests.

---

## Packaging, tooling & ops — what to do

- One source of metadata: `pyproject.toml` (PEP 621). Reproducible env via uv: `uv.lock` committed, interpreter pinned, CI `uv sync --frozen`.
- Configure Ruff, mypy, pytest in `pyproject.toml`; the same commands run locally and in CI.
- Dev/test/docs deps in dependency groups, not in the runtime set. Published packages: semver, `CHANGELOG`, `py.typed`, tested build.
- Logging module (or structlog), never `print`. Configure logging at the entry point; libraries use `NullHandler`.
- Structured logs with a correlation ID; immutable, versioned, traceable deploy artifacts; reviewed, reversible migrations.

## Packaging, tooling & ops — what NOT to do

- Don't add `setup.py` alongside `pyproject.toml`. Don't install from floating ranges in CI — install from the lock.
- Don't put runtime config in code. Don't ship a release without a tag, a changelog, and a traceable commit.
- Don't configure global logging from inside a library.

---

## When in doubt

1. Re-read the constitution section that governs the area you're touching.
2. If a behavior is missing or ambiguous, **propose an amendment** (or an ADR via `/speckit.decision.new`) rather than improvising.
3. If a directive blocks a legitimate goal, raise it — don't quietly violate it. A waiver with an owner and an expiry beats a silent regression.
