# Python Project Preset

A Spec Kit preset for building **state-of-the-art, type-safe Python** with
Spec-Driven Development — for *any* Python project: web service, CLI, library,
data pipeline, or automation.

This preset ships **behaviors, not a tech stack**. It does not pick your web
framework, ORM, validation library, or runtime — but it encodes, and
mechanically enforces, what every part of a quality Python codebase must do.
The one fixed thing is the **toolchain baseline**: `uv` + `Ruff` +
`mypy --strict` + `pytest`.

## What's inside

| File | Role |
|---|---|
| `templates/constitution-template.md` | The project **directive**. Replaces the core constitution template. Phased, criticality-tagged behaviors across Type-Safety, Code Quality, Architecture, Data/Validation, Errors, Concurrency, Security, Performance, Testing, Packaging, and Operations. |
| `templates/agent-context.md` | The **global agent rules** — a compressed, always-on operating manual. Mirror into `AGENTS.md` / `CLAUDE.md` / `.github/copilot-instructions.md` / `GEMINI.md`. |
| `commands/speckit.constitution.scan.md` | `/speckit.constitution.scan` — scan the repo (pyproject, tooling signals, source layout, Markdown docs) and export `.specify/memory/constitution.md` with a Sync Impact Report mapping evidence to directives. |
| `commands/speckit.feature.md` | `/speckit.feature` — **runs a clarification round first** (up to 5 recommended-default questions), then scaffolds a layered, `mypy --strict`-clean feature slice: contracts → domain → repository Protocol → pure Result services → interface surface → tests. |
| `commands/speckit.plan.md` | `/speckit.plan` — decompose a feature into layers, data flow, error taxonomy, security checklist, and a testing plan, tagged with Phase and Criticality. |
| `commands/speckit.tasks.md` | `/speckit.tasks` — turn a plan into a dependency-ordered task list with binary acceptance criteria and directive references. |
| `commands/speckit.scaffold.module.md` | `/speckit.scaffold.module` — scaffold one typed module set for an entity (no interface surface, no clarification). |
| `commands/speckit.audit.md` | `/speckit.audit` — regex audit against the constitution; persists JSON and prints a prioritized report by severity and section. |
| `commands/speckit.audit.deep.md` | `/speckit.audit.deep` — audit + `ruff check` + `mypy --strict` + `pytest` + `pip-audit` + LLM file-level confirmation and cross-file pattern analysis. |
| `commands/speckit.adr.new.md` | `/speckit.adr.new` — scaffold a MADR 4 (full) ADR at `docs/adr/NNNN-<slug>.md`; auto-numbers, links the commit, updates the index. |
| `commands/speckit.adr.supersede.md` | `/speckit.adr.supersede` — mark an ADR superseded and scaffold its replacement, preserving the audit trail. |
| `commands/speckit.adr.audit.md` | `/speckit.adr.audit` — audit the codebase against accepted ADRs' `audit:` (forbid/require/prefer) rules; honors `.specify/waivers.yml`. |
| `commands/speckit.docs.sync.md` | `/speckit.docs.sync` — sync agent context files from `agent-context.md`, with a diff before writing. |
| `commands/speckit.context.refresh.md` | `/speckit.context.refresh` — regenerate `.specify/memory/context-pack.md` from ADRs, plans, CHANGELOG, waivers, and session logs. |
| `commands/speckit.help.md` | `/speckit.help` — list every command grouped by phase of use with a state-aware "suggested next". |
| `scripts/bash/scan-repo.sh` | Repository inventory scanner — emits JSON per `scripts/SCHEMA.md` (pyproject, tooling signals, source layout, async/`type: ignore`/bare-except counts, Markdown inventory, git metadata). |
| `scripts/bash/audit-codebase.sh` | Rule-based audit engine — high-signal regex rules across Type-Safety, Quality, Architecture, Data, Errors, Security, Performance, Testing, and Packaging, with `--paths` / `--rules` / `--sections` / `--severity` filters. |
| `scripts/SCHEMA.md` | The stable JSON contract between the scripts and the commands (`schema_version: "1.0"`). |

## Operating framework

Every directive is tagged with a **Phase** and a **Criticality** (the
Type-Safety section adds a **Scope**: `App` / `Lib` / `Both`):

- **Phase** — when it must hold: `P1 Foundation` → `P2 MVP` → `P3 Hardening` → `P4 Scale` (continuous).
- **Criticality** — how strictly: `Critical` (blocks release) · `High` (needs an approved, time-bound exception) · `Medium` (default) · `Low` (recommended).

This lets a team enforce the right things at the right time — a green-field CLI
spike doesn't need the same controls as a production service, but both ratchet
toward the full standard as they mature.

## Coverage

- **Core principles** — Type-safety without escape hatches · explicit validated boundaries · pure core, imperative shell · typed intentional errors · determinism & reproducibility · tests as design · security by default · quality by default.
- **Type Safety & Static Analysis** — `mypy --strict`, no `Any` in public APIs, no bare `# type: ignore`, `Protocol` seams, branded `NewType` ids, `Literal`/`Enum`/`assert_never`, `py.typed`.
- **Code Quality & Style** — Ruff as the single linter+formatter, PEP 8/257, SRP, guard clauses, self-documenting names, Rule of Three.
- **Architecture & Design** — DIP/dependency injection, domain vs persistence vs wire types, composition over inheritance, acyclic modules.
- **Data, Validation & Boundaries** — parse-don't-validate, schema-validated inputs, typed settings at startup, DTOs, source-of-truth type generation, `Result` for expected failures.
- **Error Handling & Resilience** — no bare `except`, typed error hierarchies, `raise ... from`, context managers, timeouts, bounded retries, idempotency.
- **Concurrency & Async** — never block the event loop, manage every task, protect shared state, GIL-aware parallelism, bounded concurrency.
- **Security** — secrets hygiene, hostile-input parsing, no `eval`/`shell=True`/string-SQL/insecure-deserialization, password hashing, path confinement, TLS, least privilege, dependency scanning.
- **Performance** — measure before optimizing, right data structures, avoid accidental O(n²), pooling, streaming, deliberate caching.
- **Testing** — pytest, pure unit tests with no mocks, deterministic, integration at real boundaries, property-based tests, regression-per-bug.
- **Packaging, Tooling & Dependencies** — `pyproject.toml` single source, reproducible uv environments, dependency groups, version-matrix testing, semver + `py.typed` + tested builds for published packages.
- **Observability & Operations** — `logging` not `print`, structured logs with correlation ids, CI gates, immutable traceable artifacts, reviewed reversible migrations, health-gated rollouts.

## Install (local development)

```bash
# Using the specify CLI's preset mechanism:
specify preset add --dev ./presets/python
specify preset resolve constitution-template   # should resolve to this preset
```

Then generate the project constitution:

```bash
# Interactive draft from a prompt + repo context:
/speckit.constitution

# Or scan-driven — inventories pyproject + tooling + source layout + docs and
# exports a properly-structured constitution with a Sync Impact Report:
/speckit.constitution.scan
```

Both produce `.specify/memory/constitution.md` — the project's living directive.

## Typical workflow

```
1. /speckit.constitution.scan     # generate the project constitution
2. /speckit.docs.sync             # wire agent context files
3. /speckit.context.refresh       # build the first context pack

# for each feature:
4. /speckit.plan <feature>        # decompose the feature
5. /speckit.tasks                 # generate ordered tasks
6. /speckit.feature <feature>     # clarify, then scaffold the typed slice
7. ... implement ...
8. /speckit.adr.new <decision>    # record architectural decisions as they're made
9. /speckit.audit                 # pre-PR quality gate (constitution rules)
10. /speckit.adr.audit            # pre-PR quality gate (decision-specific rules)
11. /speckit.audit.deep           # pre-release gate (ruff + mypy + pytest + pip-audit)

# end of each session:
12. /speckit.context.refresh      # refresh the snapshot for the next session
```

## Governance

The constitution **supersedes ad-hoc conventions**. When a directive here
conflicts with a tutorial, a library changelog, or an LLM suggestion, the
constitution wins until it is formally amended via PR with a changelog entry —
and, where criticality or phase changes, a migration plan for affected code.
Significant decisions are recorded as ADRs. Waivers for Critical or High
directives must carry an owner, a reason, and an expiry within one release
cadence.
