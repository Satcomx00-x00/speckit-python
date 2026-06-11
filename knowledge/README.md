# Knowledge Base

The deep-reference layer for this Python Spec-Driven-Development project.

The project constitution (`.specify/memory/constitution.md`) states the directives;
the agent operating rules (`AGENTS.md` / `CLAUDE.md`) state the always-on summary; and
the skills (`skills/speckit-*/SKILL.md`) point here when a task needs the full reasoning,
worked examples, and reviewer checklists behind a directive. This base is installed into a
target project at `.specify/memory/knowledge/`.

Each file is self-contained: an agent reads only the one file relevant to the task at hand
(progressive disclosure). The files do not contradict the constitution — they expand it.

## Topics

| File | Covers |
|---|---|
| [type-safety.md](type-safety.md) | `mypy --strict`, no `Any`, `NewType`, `Protocol`, `Literal`/`Enum`/`assert_never`, `py.typed`, `TYPE_CHECKING`. |
| [code-quality.md](code-quality.md) | Ruff as the single linter/formatter, PEP 8/257, SRP, guard clauses, naming, Rule of Three. |
| [architecture.md](architecture.md) | Pure core / imperative shell, DIP + dependency injection, `Protocol` seams, domain vs persistence vs wire types, composition over inheritance. |
| [data-and-boundaries.md](data-and-boundaries.md) | Parse-don't-validate, schema validation, typed settings at startup, DTOs, `Result` for expected failures. |
| [error-handling.md](error-handling.md) | No bare `except`, typed error hierarchy / `Result`, `raise ... from`, context managers, timeouts, bounded retries, idempotency. |
| [concurrency.md](concurrency.md) | Don't block the event loop, manage tasks, locks/queues, GIL-aware threads vs processes, bounded concurrency. |
| [security.md](security.md) | Secrets hygiene, no `eval`/`exec`, no `shell=True`, parameterized SQL, no `pickle`/`yaml.load` on untrusted bytes, argon2/`secrets`, path confinement, TLS verification, least privilege, `pip-audit`. |
| [performance.md](performance.md) | Profile before optimizing, right data structures, avoid O(n²), pooling/timeouts, streaming/generators, deliberate caching. |
| [testing.md](testing.md) | pytest, pure unit tests without mocks, injected clock/RNG, fixtures/parametrization, integration at real boundaries, Hypothesis, regression-per-bug. |
| [packaging.md](packaging.md) | `pyproject.toml` as single source, `uv lock` + pinned interpreter, dependency groups, version matrix, semver + `py.typed` for libraries. |
| [observability.md](observability.md) | Logging not `print`, `NullHandler` in libraries, structured logs + correlation id, CI gates, immutable traceable artifacts, reviewed reversible migrations. |

## How to use

1. Identify the area of the task (typing, errors, security, ...).
2. Open the single matching topic file — not the whole base.
3. Read its `## Directives` table to know the Phase and Criticality that apply, then apply
   the `## Patterns` and run the `## Checklist`.
4. If a directive seems missing or ambiguous, propose a constitution amendment or an ADR
   rather than improvising. The constitution wins on any conflict.
