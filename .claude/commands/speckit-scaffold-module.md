---
description: >-
  Scaffold a single state-of-the-art Python module set for one entity:
  contracts (parse-don't-validate), domain model (branded ids, pure
  transitions), a repository Protocol + in-memory adapter, a pure
  Result-returning service with injected dependencies, and matching pytest
  unit tests. Every file is mypy --strict clean and Ruff-clean. Lighter than
  /speckit-feature — no interface surface, no clarification round.
handoffs:
  - label: Add an interface surface
    agent: speckit-feature
    prompt: Wrap this module in an API route / CLI command for the feature in $ARGUMENTS.
---

## User Input

```text
$ARGUMENTS
```

Parse the first positional argument as the **entity name** (`snake_case` slug → `PascalCase` type). Flags:

| Flag | Meaning | Default |
|---|---|---|
| `--package <path>` | Source package root | inferred (`src/<pkg>` or `<pkg>`) |
| `--fields <list>` | `name:type` field definitions | minimal stub |
| `--store <kind>` | Reference adapter: `memory` · `sqlalchemy` · `file` | `memory` |
| `--async` / `--sync` | I/O style | inferred from repo |
| `--validation <lib>` | `pydantic` · `dataclass` · `attrs` | inferred |
| `--no-tests` | Skip the test file | generate tests |
| `--dry-run` | Print instead of write | write |

If the entity name is missing, ask for it.

## Pre-Execution Checks

- Check `.specify/extensions.yml` for `hooks.before_scaffold`; apply standard hook-processing.
- Detect source layout, async/sync, and validation lib from `pyproject.toml` and existing code. Match the repo — never impose a layout it doesn't use.

## What it generates

Generate the same five-file shape as `/speckit-feature` Phases 1–4 and 7, for a single entity, with the user's `--fields` filled in concretely:

```
<pkg>/<entity>/contracts.py     ← Create/Update input models + output DTO (precise constraints, extra="forbid")
<pkg>/<entity>/models.py        ← @dataclass(frozen=True, slots=True) domain model; <Entity>Id = NewType(...)
<pkg>/<entity>/repository.py    ← <Entity>Repository(Protocol) + chosen reference adapter
<pkg>/<entity>/service.py       ← <Entity>Service: injected repo/clock/id-factory; Result[T, E] returns
tests/<entity>/test_service.py  ← pure unit tests (in-memory repo, frozen clock, seeded ids; no mocks)
```

Follow the exact patterns and checklists in `speckit.feature.md` Phases 1–4 and 7. Key invariants that MUST hold in every generated file:

- Full type annotations; `mypy --strict` clean; no `Any`, no bare `# type: ignore`.
- Branded `NewType` ids; frozen dataclasses for value objects; pure state transitions.
- Service depends on a `Protocol`, not a concrete store; deps injected, never constructed inline.
- Expected failures returned as `Err(...)`; narrowest exceptions otherwise.
- For `--store sqlalchemy`: parameterized/ORM queries only — never string-built SQL.
- Tests deterministic: injected clock and id factory, zero mocks.

## After scaffolding

Print the file list and the verification command:

```
ruff check && mypy --strict <pkg>/<entity> && pytest tests/<entity>
```

Suggested next: `/speckit-feature <entity>` to add an API/CLI surface, or `/speckit-audit` to verify compliance.

## Post-Execution Hooks

Check `.specify/extensions.yml` for `hooks.after_scaffold`. Apply standard hook-processing.
