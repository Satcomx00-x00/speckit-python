# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-06-11

### Added

- **Python constitution** (`presets/python/templates/constitution-template.md`)
  — phased, criticality-tagged behavioral directives across Type-Safety, Code
  Quality, Architecture, Data/Validation, Errors, Concurrency, Security,
  Performance, Testing, Packaging, and Operations. Toolchain baseline:
  uv + Ruff + mypy `--strict` + pytest.
- **Agent operating rules** (`presets/python/templates/agent-context.md`),
  mirrored into `AGENTS.md` and referenced from `CLAUDE.md`.
- **Slash commands** (`presets/python/commands/`, installed dash-form in
  `.claude/commands/`):
  - `/speckit.feature` — clarify-first, layered, typed feature scaffold.
  - `/speckit.constitution.scan`, `/speckit.plan`, `/speckit.tasks`,
    `/speckit.scaffold.module`.
  - `/speckit.audit`, `/speckit.audit.deep`, `/speckit.adr.audit`.
  - `/speckit.adr.new`, `/speckit.adr.supersede`, `/speckit.context.refresh`,
    `/speckit.docs.sync`, `/speckit.help`.
- **Audit tooling** (`presets/python/scripts/bash/`) — `scan-repo.sh` repository
  inventory and `audit-codebase.sh` rule-based engine, with a stable JSON
  contract in `scripts/SCHEMA.md`.
- **ADR memory layer** (`docs/adr/`) — MADR 4 template, index, and ADR-0001
  recording the foundational toolchain decision.
- **Workflow** (`workflows/python-feature/`) — end-to-end feature delivery
  cycle with uv/Ruff/mypy/pytest quality gates.
- **Canonical `pyproject.toml`** configuring Ruff, mypy `--strict`, and pytest.
- This repository's own filled constitution at
  `.specify/memory/constitution.md` (phase P1).
