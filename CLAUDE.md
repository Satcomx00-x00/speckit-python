# CLAUDE.md

This repository is a **Python-specialized Spec Kit**: a constitution, slash
commands, workflows, and an ADR memory layer that drive AI coding agents
through state-of-the-art, type-safe Python development.

## Read these first, every session

1. **`.specify/memory/constitution.md`** — the authoritative project directive.
   It governs behavior and **supersedes anything here on conflict**.
2. **`AGENTS.md`** — the compressed, always-on operating rules (mirror of
   `presets/python/templates/agent-context.md`). These apply on every turn.

The non-negotiable toolchain baseline is **uv** · **Ruff** (lint + format) ·
**mypy `--strict`** · **pytest**. No `Any` in public signatures, parse
untrusted input at the boundary, keep the core pure and inject side effects,
model expected failures as typed results, and never ship a quality regression.

## Slash commands

This repo installs the Python preset's commands in `.claude/commands/` using the
dash form Claude Code expects:

| Phase | Commands |
|---|---|
| Bootstrap | `/speckit-constitution-scan`, `/speckit-docs-sync` |
| Planning | `/speckit-plan`, `/speckit-tasks` |
| Implementation | `/speckit-feature` (runs a clarification round first), `/speckit-scaffold-module` |
| Quality | `/speckit-audit`, `/speckit-audit-deep`, `/speckit-adr-audit` |
| Decision memory | `/speckit-adr-new`, `/speckit-adr-supersede`, `/speckit-context-refresh` |
| Help | `/speckit-help` |

The portable spec-kit form (`/speckit.feature`, etc.) lives in
`presets/python/commands/` for installation into other agents and projects.

## Skills & knowledge base

Each command also exists as an auto-discovered **skill** at
`skills/speckit-*/SKILL.md` (generated from the commands by
`scripts/build-skills.py` — edit the command, then run the generator; CI checks
`--check`). Skills reference the **knowledge base** at `knowledge/` (installed to
`.specify/memory/knowledge/`), which splits the constitution into deep,
load-on-demand topic references (`type-safety.md`, `security.md`, `testing.md`,
…). When you need depth on a topic, read just that file — don't load them all.

The toolkit installs into other projects via `./install.sh` (and is declared in
`extension.yml` for `specify extension add`). This repo dogfoods itself through
the `.claude/skills` and `.specify/memory/knowledge` symlinks.

## Working in this repo

- Command specs are Markdown with YAML front-matter under `presets/python/commands/`.
- Templates (constitution, agent-context) are under `presets/python/templates/`.
- Audit/scan scripts are under `presets/python/scripts/bash/` and must stay
  `shellcheck`-clean.
- Architectural decisions are recorded as ADRs under `docs/adr/` — add one with
  `/speckit-adr-new` when you make a decision that shapes the toolkit.
- Any example Python in command specs must itself be `mypy --strict`-clean and
  Ruff-clean — the toolkit must practice what it preaches.
