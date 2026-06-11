---
id: 0001
title: Adopt Spec-Driven Development for Python with a strict toolchain
status: accepted
phase: P1
criticality: Critical
owner: Satcomx00-x00
date: 2026-06-11
commit: ece2230
supersedes: null
superseded_by: null
rfc: null
constitution_refs:
  - TYPE.ANY.any-annotation
  - PKG.LOCK.reproducible-env
  - QUAL.RUFF.single-linter
  - TEST.PYTEST.green-ci
tags:
  - meta
  - toolchain
  - process
audit:
  require:
    - pattern: "strict\\s*=\\s*true"
      paths: ["pyproject.toml"]
      message: "mypy must run in strict mode (ADR-0001)"
  forbid:
    - pattern: "^\\s*\\[tool\\.black\\]"
      paths: ["pyproject.toml"]
      message: "Ruff is the single formatter; no second formatter (ADR-0001)"
---

# ADR 0001: Adopt Spec-Driven Development for Python with a strict toolchain

## Context and Problem Statement

This repository provides a Python-specialized **Spec Kit** — a constitution,
a set of slash commands, workflows, and an ADR memory layer that drive AI
coding agents through structured, high-quality Python development. It mirrors
the architecture of the upstream Next.js preset but targets Python projects of
any shape (web service, CLI, library, data pipeline, automation).

How should the toolkit define "state-of-the-art, ultra-high-quality, type-safe
Python", concretely enough that an AI agent can enforce it on every change,
without locking adopters into a particular web framework, ORM, or runtime?

A vague answer ("write clean, typed code") produces drift. A framework-locked
answer ("use FastAPI + SQLAlchemy") excludes most Python projects. We need a
**behavioral** standard plus a **non-negotiable toolchain baseline** that
applies regardless of stack.

## Decision Drivers

- Type-safety that a machine can verify, not just aspire to.
- Stack-agnosticism — the preset must serve a CLI, a library, and a service equally.
- Reproducibility — the environment must rebuild identically from a lockfile.
- One obvious way to lint, format, type-check, and test — no bikeshedding.
- Enforceability — every directive should map to an audit rule or a CI gate.
- Low ceremony for adopters — copy the config and the standard holds.

## Considered Options

1. **Behavioral constitution + fixed toolchain (uv + Ruff + mypy `--strict` + pytest)**
2. **Framework-locked preset** (e.g. FastAPI + SQLAlchemy + Pydantic scaffolds only)
3. **Tool-agnostic guidelines** (principles only; let each project pick all tooling)

## Decision Outcome

**Chosen option**: "Behavioral constitution + fixed toolchain (uv + Ruff + mypy
`--strict` + pytest)".

**Rationale**: The constitution encodes *behaviors* (parse-don't-validate,
pure-core/imperative-shell, typed errors, security by default) so it applies to
any Python project, while a small, fixed toolchain makes those behaviors
**verifiable**: mypy `--strict` proves type-safety, Ruff proves style and
catches security smells, uv proves reproducibility, and pytest proves behavior.
This is the modern (2026) consensus stack for serious Python and lets the
`/speckit.audit` and `/speckit.adr.audit` commands check compliance
mechanically rather than relying on reviewer memory.

### Confirmation

- `pyproject.toml` configures `[tool.ruff]`, `[tool.mypy] strict = true`, and
  `[tool.pytest.ini_options]`; the `audit:` block on this ADR asserts strict
  mypy and the absence of a second formatter.
- `/speckit.audit` (constitution rules) and `/speckit.audit.deep` (ruff + mypy
  `--strict` + pytest + pip-audit) pass on adopting projects.
- Review date: revisit if the Python typing ecosystem shifts materially (e.g. a
  successor to mypy/pyright becomes standard) or if uv is superseded.

## Consequences

### Positive

- Every quality claim is machine-checkable; agents can self-verify before PR.
- Adopters get a working, opinionated config by copying `pyproject.toml`.
- The standard is portable across the entire Python project space.

### Negative

- Teams already standardized on Poetry/Black/Flake8 must migrate or waive.
- mypy `--strict` has a learning curve and will flag pre-existing loose code.
- A fixed toolchain is a maintenance commitment as those tools evolve.

### Neutral

- Tool choices (web framework, ORM, validation library) remain per-project and
  are recorded in their own ADRs, not dictated here.
- New projects start at constitution phase **P1** and ratchet toward P4.

## Pros and Cons of the Options

### Behavioral constitution + fixed toolchain

**Pros**:
- Stack-agnostic behaviors + machine-verifiable enforcement.
- One obvious toolchain; minimal bikeshedding.

**Cons**:
- Imposes a migration cost on teams using different tools.

### Framework-locked preset

**Pros**:
- Richer, more concrete scaffolds for that one stack.

**Cons**:
- Excludes most Python projects; brittle as the framework evolves.

### Tool-agnostic guidelines

**Pros**:
- Maximum flexibility.

**Cons**:
- Unenforceable; "type-safe" becomes a slogan, not a gate. Drift is inevitable.

## More Information

- Related ADRs: none (this is the foundational record).
- Constitution sections enforced: Type-Safety, Code Quality & Style, Packaging
  & Tooling, Testing (and, by extension, every section's Quality Gates).
- Migration plan: adopters copy `pyproject.toml`, run `uv sync`, then
  `/speckit.constitution.scan` to generate their own phased constitution.
- Review date: 2027-06-11 (annual), or sooner if the toolchain consensus shifts.
