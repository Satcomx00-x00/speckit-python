---
description: >-
  Python-shaped task generation. Converts a feature plan into a dependency-ordered
  task list — contracts first, then domain, repository, service, surface, wiring,
  and tests — with Python-idiomatic titles, acceptance criteria that reference
  constitution directives, and explicit Phase tags.
handoffs:
  - label: Scaffold the feature
    agent: speckit.feature
    prompt: Scaffold the feature these tasks describe.
---

## User Input

```text
$ARGUMENTS
```

Optional first arg: a path to a `plan.md`. If omitted, locate the active feature plan; if none exists, ask the user to run `/speckit.plan` first (do not invent a plan).

## Pre-Execution Checks

- Check `.specify/extensions.yml` for `hooks.before_tasks`; apply standard hook-processing.
- Load the plan and the constitution. Tasks must inherit the plan's Phase/Criticality tags and reference real directives.

## Outline

Emit an ordered, checkable task list. Order strictly by dependency so each task is mergeable on its own and the build never has a missing-import gap. Every task has: an ID, a Phase tag, a one-line title, the file(s) it touches, **binary** acceptance criteria, and the directive(s) it satisfies.

Use this canonical ordering (drop async if the project is sync; drop a layer if the plan omits it):

```
T01 [P1] Contracts — input + output models
    Files: <pkg>/<feature>/contracts.py
    Done when:
      [ ] Every input field has a precise constraint; unknown keys rejected
      [ ] Output DTO omits secrets/internal fields
      [ ] mypy --strict clean; ruff clean
    Directives: Data/Validation (Critical); Type-Safety (Critical)

T02 [P1] Domain model — branded ids + pure transitions
    Files: <pkg>/<feature>/models.py
    Done when:
      [ ] IDs are NewType, not raw str
      [ ] State transitions are pure (no I/O, no clock, no RNG)
    Directives: Architecture (High); Type-Safety (High)

T03 [P2] Repository — Protocol + in-memory adapter
    Files: <pkg>/<feature>/repository.py
    Done when:
      [ ] Service-facing Protocol defined; in-memory adapter implements it structurally
      [ ] SQL adapter (if any) uses parameterized queries only
    Directives: Architecture/DIP (High); Security/SQL (Critical)

T04 [P1] Service — use cases, Result, injected deps
    Files: <pkg>/<feature>/service.py
    Done when:
      [ ] repo, clock (now), id factory injected; no direct I/O construction
      [ ] Expected failures returned as Err(...); narrowest exceptions otherwise
    Directives: Pure core (Critical); Errors (High)

T05 [P1] Service unit tests — pure, no mocks
    Files: tests/<feature>/test_service.py
    Done when:
      [ ] Happy path, NOT_FOUND, and each documented error path covered
      [ ] Frozen clock + seeded id factory; zero mocks; deterministic
    Directives: Testing (Critical)

T06 [P2] Surface — API route / CLI command / lib export / worker task
    Files: <pkg>/<feature>/{router,cli,tasks}.py
    Done when:
      [ ] Thin: parse → (authorize) → service → map Result → response/exit
      [ ] Errors mapped to correct status/exit codes; no internals leaked
    Directives: Boundaries (Critical); Security (Critical)

T07 [P2] Wiring — composition root supplies concrete deps
    Files: <pkg>/<feature>/__init__.py or app wiring
    Done when:
      [ ] Concrete repo/clock/id-factory wired; new config in typed settings model
    Directives: Architecture (High); Packaging/config (High)

T08 [P2] Boundary + integration tests
    Files: tests/<feature>/test_contracts.py, tests/<feature>/test_<surface>.py
    Done when:
      [ ] Invalid input rejected (length/type/extra keys)
      [ ] Surface exercised against an ephemeral store
    Directives: Testing (High)

T09 [P2] Ship gate
    Done when:
      [ ] ruff format --check && ruff check && mypy --strict && pytest all green
      [ ] CHANGELOG updated; ADR recorded if a decision was made; uv.lock updated if deps changed
    Directives: Quality Gates
```

Adjust task contents to the plan's specifics (entity fields, surface, error modes). Keep acceptance criteria **binary** — a reviewer must be able to mark each `[ ]` true/false without judgment calls. Flag any criterion that contains "should", "ideally", or "if possible" and rewrite it.

## Post-Execution Hooks

Check `.specify/extensions.yml` for `hooks.after_tasks`. Apply standard hook-processing.

Suggested next: `/speckit.feature <feature>` to scaffold, or start at T01 and implement in order.
