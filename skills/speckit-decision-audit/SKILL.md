---
name: speckit-decision-audit
description: "Audit the codebase against accepted ADRs. For each ADR, surface code patterns that contradict the decision and code patterns the ADR mandates but cannot be found. Severity is derived from the ADR's `criticality` field. Findings respect the central waiver registry at `.specify/waivers.yml`. Use when the user wants to check the code against accepted ADRs."
---

# Speckit Decision Audit

> This skill is generated from the Python preset command
> `presets/python/commands/speckit.decision.audit.md` by `scripts/build-skills.py`.
> Edit the command (or the knowledge map in the generator), then regenerate.

## User Input

```text
$ARGUMENTS
```

Parse from `$ARGUMENTS`:

| Token | Meaning | Default |
|---|---|---|
| `--adr <id>` | Audit only the listed ADR(s) — comma-separated | all `accepted` ADRs |
| `--phase <p>` | Audit only ADRs whose phase ≤ given phase | current project phase |
| `--paths <list>` | Restrict the scan to these paths | whole repo (excludes `.git`, `.venv`, `__pycache__`, `.mypy_cache`) |
| `--include-proposed` | Also audit `proposed` ADRs (advisory only) | off |
| `--format <fmt>` | `human` / `json` / `markdown` | `human` |
| `--output <path>` | Persist a copy of the report | `.specify/audits/adr/<ISO-timestamp>.<fmt>` |

## Pre-Execution Checks

Check for `.specify/extensions.yml`. Look for hooks under `hooks.before_audit`. Apply standard hook-processing.

Verify `docs/adr/` exists. If not, abort with: `No ADRs found. Run /speckit-decision-new first.`

Verify `.specify/memory/constitution.md` exists. If not, warn: `No constitution found; criticality phase-gating will fall back to the ADR's own criticality field.`

## Outline

### 1. Build the ADR index

Walk `docs/adr/*.md`. For each file, parse the front-matter. Collect:
- `id`, `title`, `status`, `phase`, `criticality`
- `constitution_refs` (used to derive specific patterns to check)
- An optional `audit:` block — if present, drives the checks (see step 2)

Skip ADRs whose `status` is not `accepted` unless `--include-proposed` is set.

### 2. Resolve audit rules per ADR

An ADR can declare its own checks in front-matter:

```yaml
audit:
  forbid:
    - pattern: "pickle\\.loads\\("
      paths: ["src/**/*.py"]
      message: "Insecure deserialization forbidden — use a typed schema (ADR-0042)"
  require:
    - pattern: "from\\s+__future__\\s+import\\s+annotations"
      paths: ["src/<pkg>/domain/**/*.py"]
      message: "Every domain module must declare `from __future__ import annotations` (ADR-0017)"
  prefer:
    - pattern: "import\\s+sqlalchemy|from\\s+sqlalchemy\\s+import"
      message: "SQLAlchemy is the chosen persistence layer (ADR-0042) — prefer over raw psycopg/sqlite3"
```

If `audit:` is absent, the ADR is **audit-advisory only** — surface its title and ID but do not produce code-level findings. (Prompt the user to add an `audit:` block when implementing the decision.)

### 3. Resolve waivers

Read `.specify/waivers.yml`. Each entry:

```yaml
- id: ADR-0042/forbid#1
  reason: Legacy import job — to be removed by 2026-07-01
  owner: @alice
  expires: 2026-07-01
```

A finding matches a waiver when its `<adr-id>/<rule-bucket>#<pattern-index>` equals the waiver `id`. Waivers past `expires` are reported as expired and do NOT suppress the finding.

### 4. Run the scans

For each ADR's `audit:` block:

| Rule bucket | Behavior | Severity |
|---|---|---|
| `forbid` | Matching code is a finding | derived from ADR `criticality` |
| `require` | Missing match in the listed paths is a finding | derived from ADR `criticality` |
| `prefer` | Matching alternative patterns is a finding | `Low` regardless of criticality |

Use `xargs -P` or equivalent for parallel grep, matching the scaling approach in `audit-codebase.sh`. Cap matches per pattern at `--max-findings-per-rule` (default 50).

### 5. Phase-gate the findings

For each finding, compare ADR `phase` vs. project `current_phase` (from constitution). If the ADR's phase is in the future, downgrade the finding severity by one level (`Critical` → `High`, `High` → `Medium`, etc.) and label it `(future-phase)`.

### 6. Render the report

```
## ADR Audit Report

**Project phase**: <P1-P4>
**ADRs scanned**: <count> (accepted: <n>, proposed: <n>, audit-advisory only: <n>)
**Total findings**: <n> (Critical: <n>, High: <n>, Medium: <n>, Low: <n>)
**Waivers applied**: <n> (active: <n>, expired: <n>)

### Critical

#### ADR-0017 — "Domain modules must declare `from __future__ import annotations`"
*Rule*: `require` / pattern #1
*Constitution refs*: TYPE.FUTURE.future-annotations

- `src/billing/domain/invoice.py` — missing `from __future__ import annotations`
  *Remediation*: Add `from __future__ import annotations` as the first import.

#### ADR-0042 — "Adopt SQLAlchemy 2.0 typed ORM for persistence" *(future-phase: P3)*
*Rule*: `forbid` / pattern #2
*Constitution refs*: SEC.SQL.string-sql

- `src/billing/repository.py:31` — uses `pickle.loads(` on cached rows
  *Remediation*: Replace insecure deserialization with a typed schema. See ADR-0042 §Migration plan.
  *Waiver*: none

### High
... (similar structure) ...

### Audit-advisory ADRs (no `audit:` block)

These ADRs were not checked at the code level. Consider adding `audit:` rules
so they're enforced rather than aspirational.

- ADR-0033 — "Adopt OpenTelemetry for tracing"
- ADR-0051 — "All worker tasks must be idempotent"

### Expired waivers (no longer suppressing findings)

- `ADR-0042/forbid#2` expired 2026-04-12 (owner @alice). Renew or remediate.
```

If `--format json` is set, emit a machine-readable shape mirroring `scripts/SCHEMA.md`. If `--format markdown`, emit the rendered report.

### 7. Persist and exit

Write a copy to `.specify/audits/adr/<ISO-timestamp>.<fmt>`.

Exit codes:
- `0` if no Critical findings (advisory: any High count > 0 prints a warning)
- `1` if any Critical finding is present and not waived
- `2` if any Critical or High waiver has expired

## Post-Execution Hooks

Check `.specify/extensions.yml` for `hooks.after_audit`. Apply standard hook-processing.

---

## Knowledge base

The project constitution at `.specify/memory/constitution.md` is authoritative. For deep,
task-specific guidance (directives + Do/Don't code patterns), load only the
relevant reference file from the installed knowledge base — do not read them all:

- **security** → `.specify/memory/knowledge/security.md`
- **architecture** → `.specify/memory/knowledge/architecture.md`
