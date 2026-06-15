# Architecture Decision Records

This directory contains the project's Architecture Decision Records (ADRs) in
[MADR 4](https://adr.github.io/madr/) (full) format. The records are the
durable rationale for the choices that shape the codebase. They supersede
tutorials, blog posts, and AI suggestions — when a directive there conflicts
with one of those, the ADR wins until a new ADR is recorded that supersedes it.

## How to use

- Create one with `/speckit.decision.new "<decision title>"` (or `/speckit-decision-new`).
- Replace one with `/speckit.decision.supersede <id> "<new title>"`.
- Enforce them against the code with `/speckit.decision.audit` — accepted ADRs may
  carry an `audit:` front-matter block of `forbid` / `require` / `prefer` rules.
- `0000-template.md` is the canonical template; copy it (or let `/speckit.decision.new`
  scaffold it) — it is not itself a decision and is excluded from the index.

## Lifecycle

`proposed` → `accepted` → (`deprecated` | `superseded`). A `rejected` ADR is
kept for the audit trail. A superseded ADR retains its content and gains a
`superseded_by` link; the replacement carries the prior `constitution_refs`
forward by default.

## Index

| ID | Title | Status | Phase | Criticality | Date |
|---|---|---|---|---|---|
| [0001](./0001-adopt-spec-driven-development-for-python.md) | Adopt Spec-Driven Development for Python with a strict toolchain | accepted | P1 | Critical | 2026-06-11 |
| [0002](./0002-ship-skills-and-knowledge-base-self-propelled.md) | Ship agent skills and a knowledge base inside the repo, installable via specify | accepted | P1 | High | 2026-06-11 |
