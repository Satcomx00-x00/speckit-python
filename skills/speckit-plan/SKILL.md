---
name: speckit-plan
description: "Python-specialized feature planning. Decomposes a feature into typed boundary contracts, domain models, repository/persistence seams, pure services, the interface surface (API/CLI/lib/worker), concurrency model, error taxonomy, security checklist, and a testing plan — every item tagged with Phase and Criticality and grounded in the project constitution. Use when the user wants to plan or decompose a Python feature before implementing it."
---

# Speckit Plan

> This skill is generated from the Python preset command
> `presets/python/commands/speckit.plan.md` by `scripts/build-skills.py`.
> Edit the command (or the knowledge map in the generator), then regenerate.

## User Input

```text
$ARGUMENTS
```

Parse the first positional argument as the feature name/slug. Treat the rest as free-form context (constraints, stack hints, scope).

## Pre-Execution Checks

- Check `.specify/extensions.yml` for `hooks.before_plan`; apply standard hook-processing.
- Read `.specify/memory/constitution.md` if present — every plan item must reference the directives it satisfies. If absent, note it and recommend `/speckit-constitution-scan`.
- Detect the project shape (source layout, surface, async vs sync, validation lib, test layout) exactly as `/speckit-feature` does, so the plan matches the repo.

## Outline

Produce a single Markdown plan document. Do **not** write code — describe what will be built and why, tagged so `/speckit-tasks` can order it. If a spec file exists for this feature, write the plan to `<feature-dir>/plan.md`; otherwise print it.

### 1. Summary & decisions

- One-paragraph feature summary and the user-facing outcome.
- A **Decisions** table: surface, persistence, I/O style, validation lib, error style, key invariants, non-goals. (If these are ambiguous, recommend running `/speckit-feature` Phase 0 or `/speckit-clarify` first — don't invent them silently.)

### 2. Layer map

For each layer, list the modules/files, their responsibility, and the directives they must satisfy:

| Layer | Module | Responsibility | Phase | Crit. | Directives |
|---|---|---|---|---|---|
| Contracts | `<pkg>/<feature>/contracts.py` | Parse-don't-validate input + output DTOs | P1 | Critical | Data/Validation; Type-Safety |
| Domain | `<pkg>/<feature>/models.py` | Branded ids, invariants, pure transitions | P1 | High | Architecture; Type-Safety |
| Persistence | `<pkg>/<feature>/repository.py` | Repository `Protocol` + adapter | P2 | Critical | Architecture (DIP); Security (SQL) |
| Service | `<pkg>/<feature>/service.py` | Use cases, `Result`, injected deps | P1 | Critical | Pure core; Errors |
| Surface | `<pkg>/<feature>/{router,cli,tasks}.py` | Thin parse→service→map | P2 | High | Boundaries; Security |
| Tests | `tests/<feature>/...` | Unit (no mocks) + integration | P1 | Critical | Testing |

### 3. Data flow

- The path of a request/invocation through the layers (boundary → service → repository → back), naming the types at each hop.
- Where untrusted input is parsed, where authorization is checked, where the DTO is produced.

### 4. Error taxonomy

- The expected failure modes and how each is represented (`Result` variant or exception type) and surfaced (status/exit code). Map each to the directive in *Error Handling*.

### 5. Concurrency & performance

- Async vs sync decision and why; any blocking work that must be offloaded; concurrency bounds.
- Expected data volume and the data-structure / query implications (pagination, batching, N+1 avoidance).

### 6. Security checklist (feature-specific)

- Input parsing at every boundary; authz points; secrets/config handling; any subprocess/deserialization/SQL surfaces and how they're made safe; least-privilege notes.

### 7. Testing plan

- Unit tests (pure core, injected effects, no mocks): list the behaviors and the boundary-validation cases.
- Integration tests: which real boundaries, which ephemeral resources.
- Property-based candidates (parsers/serializers) and the regression cases to lock in.

### 8. Risks, open questions, and sequencing

- Risks and mitigations; anything still ambiguous (route to `/speckit-clarify`); the build order (matches `/speckit-tasks`).

## Post-Execution Hooks

Check `.specify/extensions.yml` for `hooks.after_plan`. Apply standard hook-processing.

Suggested next: `/speckit-tasks` to turn this plan into ordered work, or `/speckit-feature <feature>` to scaffold it.

---

## Knowledge base

The project constitution at `.specify/memory/constitution.md` is authoritative. For deep,
task-specific guidance (directives + Do/Don't code patterns), load only the
relevant reference file from the installed knowledge base — do not read them all:

- **architecture** → `.specify/memory/knowledge/architecture.md`
- **error handling** → `.specify/memory/knowledge/error-handling.md`
- **concurrency** → `.specify/memory/knowledge/concurrency.md`
- **security** → `.specify/memory/knowledge/security.md`
- **testing** → `.specify/memory/knowledge/testing.md`
- **performance** → `.specify/memory/knowledge/performance.md`
- **principles** → `.specify/memory/knowledge/principles.md`
