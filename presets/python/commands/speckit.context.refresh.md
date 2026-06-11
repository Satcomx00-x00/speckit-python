---
description: Regenerate `.specify/memory/context-pack.md` — the one-page snapshot every new AI session reads first. Aggregates the ADR index, accepted/proposed ADRs, in-flight feature plans, recent CHANGELOG entries, active and expired waivers, the current constitution phase + version, and recent session logs. Markdown-only; no external store.
---

## User Input

```text
$ARGUMENTS
```

Parse from `$ARGUMENTS`:

| Token | Meaning | Default |
|---|---|---|
| `--max-adrs <n>` | Show this many most-recent ADRs in the snapshot | `15` |
| `--max-changelog <n>` | Show this many most-recent CHANGELOG entries | `10` |
| `--include-proposed` | Include `proposed` ADRs | on |
| `--dry-run` | Print the rendered content without writing | off |
| `--output <path>` | Override the output path | `.specify/memory/context-pack.md` |

## Pre-Execution Checks

Check for `.specify/extensions.yml`. Look for hooks under `hooks.before_context_refresh`. Apply standard hook-processing.

Verify `.specify/memory/constitution.md` exists. If not, warn — the context pack still renders, but downstream commands (`/speckit.feature`, `/speckit.plan`, `/speckit.audit`) assume the constitution exists; recommend `/speckit.constitution.scan`.

## Outline

### 1. Gather inputs

Read from the following sources (skip silently if absent):

| Source | Pull |
|---|---|
| `.specify/memory/constitution.md` front-matter | `version`, `current_phase`, `ratification_date`, `last_amended_date` |
| `docs/adr/README.md` | the ADR index table (id → title → status → date) |
| `docs/adr/*.md` front-matter | id, title, status, phase, criticality, date — sorted by id desc |
| `specs/*/plan.md` or `.specify/plans/*.md` | feature name, phase, status (in-flight if not `completed`) |
| `CHANGELOG.md` (Keep-a-Changelog format) | `[Unreleased]` block + last released version block |
| `.specify/waivers.yml` | active and expired waivers |
| `.specify/sessions/*.md` (last 3 by mtime) | session title, date, summary line from front-matter |

### 2. Render the context pack

Write to `.specify/memory/context-pack.md` (unless overridden):

```markdown
<!--
GENERATED FILE — do not edit directly.
Regenerate with: /speckit.context.refresh
Source of truth lives in: docs/adr/, CHANGELOG.md, .specify/
-->

# Project Context Pack

> Read this first. Every section is a pointer to authoritative documents;
> never paraphrase it as if it were the source of truth. When the snapshot
> conflicts with the source, the source wins — regenerate this file.

**Generated**: <ISO-timestamp>
**Project phase**: <P1-P4>
**Constitution version**: <semver> (ratified <date>, last amended <date>)

## North star

<pull from constitution `mission:` / `north_star:` front-matter — one or two sentences>

## Toolchain baseline

uv · Ruff (lint + format) · mypy `--strict` · pytest. Non-negotiable; CI runs
the same commands. (Full directives: `.specify/memory/constitution.md`.)

## Accepted Architecture Decisions

The decisions below are binding. Code that contradicts them is a finding
(see `/speckit.adr.audit`).

| ID | Title | Phase | Criticality | Date |
|---|---|---|---|---|
| [ADR-0007](../../docs/adr/0007-...) | Result types over exceptions in services | P2 | Critical | 2026-05-12 |
| [ADR-0006](../../docs/adr/0006-...) | Repository Protocol seam for persistence | P1 | High | 2026-04-30 |
| ... | | | | |

*(<N> total accepted; showing most-recent <max-adrs>. Full index:
`docs/adr/README.md`.)*

## Proposed (not yet binding)

| ID | Title | Owner | Opened |
|---|---|---|---|
| ADR-0011 | Adopt structlog for structured logging | @bob | 2026-05-20 |

## In-flight feature plans

These features have a `plan.md` but are not yet marked completed.

- `invoice_export` — Phase P2 — owner @dave
  Plan: `specs/invoice_export/plan.md`

## Recent CHANGELOG entries

### [Unreleased]
- (Added) `Result[T, E]` envelope in `billing.service` — ADR-0007
- (Changed) Settings now parsed via a typed Pydantic model at startup

### [0.4.0] — 2026-05-18
- (Added) Repository Protocol seam for the user store — ADR-0006

## Active waivers

| Waiver ID | Owner | Expires | Reason |
|---|---|---|---|
| `ADR-0007/forbid#2` | @alice | 2026-07-01 | Legacy CLI path still raises |

**Expired** (still firing as findings until remediated):

| Waiver ID | Owner | Expired |
|---|---|---|
| `SEC.no-shell-true/1` | @bob | 2026-04-12 |

## Recent session logs

The last few AI sessions left these notes. Skim before starting work.

- 2026-05-24 — "Wire billing webhooks" (.specify/sessions/2026-05-24-billing-webhooks.md)
- 2026-05-23 — "Add user invitations" (.specify/sessions/2026-05-23-user-invites.md)

## Source of truth

| Concern | File |
|---|---|
| Behavioral directives | `.specify/memory/constitution.md` |
| Operating rules for AI | `.specify/presets/python/templates/agent-context.md` |
| Decisions | `docs/adr/` (index: `docs/adr/README.md`) |
| Releases | `CHANGELOG.md` |
| Waivers | `.specify/waivers.yml` |
| Per-session notes | `.specify/sessions/` |
```

### 3. Detect and report drift

After rendering, compute simple drift signals and append a final section
when any are non-empty:

```markdown
## Drift signals

- 2 ADRs accepted in the last 30 days lack an `audit:` block — they are
  enforced only by convention. Run /speckit.adr.audit and add rules.
- The constitution was last amended 124 days ago — consider re-running
  /speckit.constitution.scan.
- 3 feature plans have been in-flight for > 30 days. Stale plans become
  fiction.
- 2 waivers expired more than 14 days ago.
- `uv.lock` is newer than the last CHANGELOG edit — a dependency change may
  be unrecorded.
```

Drift signals are advisory; they do not affect exit code.

### 4. Print the summary

```
## Context pack refreshed

**File**: .specify/memory/context-pack.md
**Sections rendered**: <N>
**Drift signals**: <N>

**Next steps**:
- Reference this file at the top of CLAUDE.md / AGENTS.md / copilot-instructions
  so every new session picks it up automatically (see /speckit.docs.sync).
- Regenerate after any of: /speckit.adr.new, /speckit.adr.supersede,
  /speckit.constitution.scan, CHANGELOG edits.
- Drift signals above are not auto-fixed — handle them explicitly.
```

If `--dry-run` is set, print the rendered content and the summary; do not write.

## Post-Execution Hooks

Check `.specify/extensions.yml` for `hooks.after_context_refresh`. Apply standard hook-processing.
</content>
