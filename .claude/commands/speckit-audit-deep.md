---
description: Deep codebase audit. Runs the regex-based audit script, then layers in ruff check, ruff format --check, mypy --strict, pytest, and pip-audit, plus file-level read-throughs and cross-file LLM analysis to confirm and correlate findings. Slower than /speckit-audit but materially higher signal.
handoffs:
  - label: Open Remediation Plan
    agent: speckit-plan
    prompt: Build a plan from the deep audit findings. Sequence by criticality, group by area, scope per release.
  - label: Record an ADR
    agent: speckit-adr-new
    prompt: Record the architectural decision behind a confirmed cross-file finding (e.g. a settings-model boundary, an async/sync split) as an ADR.
---

## User Input

```text
$ARGUMENTS
```

You **MAY** consider the user input as scope hints (paths, severity floor, sections, rule filters, max findings per rule). The deep audit honors the same flags as `/speckit-audit`. If empty, audit the whole repository at default settings.

## Pre-Execution Checks

**Check for extension hooks (before deep audit)**:

- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under `hooks.before_audit_deep` first, then `hooks.before_audit`.
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally.
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable.
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation.
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Pre-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Pre-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}

    Wait for the result of the hook command before proceeding to the Outline.
    ```
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently.

## Outline

A **deep audit** is the regex-based audit *plus* five extra layers that bring the real Python toolchain — **uv**, **Ruff**, **mypy `--strict`**, **pytest** — and the LLM to bear:

1. **Lint & format ground truth** — `ruff check` and `ruff format --check`.
2. **Type ground truth** — `mypy --strict` over the package (the constitution's first test suite).
3. **Test ground truth** — `pytest -q` (collect-only or a quick run) to confirm the suite is green and collectible.
4. **Dependency posture** — `pip-audit` (or `uv pip audit`) against the resolved environment.
5. **LLM confirmation & cross-file analysis** — read flagged files in full, dedupe false positives, and verify the architectural invariants the regex pass can only hint at.

Prefer **uv** to drive each tool so it runs against the locked environment: `uv run ruff ...`, `uv run mypy ...`, `uv run pytest ...`, `uv run pip-audit`. Fall back to the bare tool on `PATH` when `uv` is absent.

The deep audit is **slower** than the standard one. Treat it as the pre-release gate, not the pre-commit gate.

Follow this flow:

### 1. Parse scope hints from `$ARGUMENTS`

Same rules as `/speckit-audit`. Translate into `--paths` / `--rules` / `--sections` / `--severity` / `--max-findings-per-rule` flags for the audit script, and reuse the same path list to scope the toolchain layers (e.g. `mypy --strict src`).

### 2. Run the regex audit (Layer 1)

```bash
bash .specify/presets/python/scripts/bash/audit-codebase.sh --json [flags...]
```

(or `pwsh .specify/presets/python/scripts/powershell/audit-codebase.ps1 -Json [...]`)

Capture the JSON output (schema per `.specify/presets/python/scripts/SCHEMA.md`). This is the **baseline finding set** that the next layers confirm and extend.

### 3. Run Ruff (Layer 2)

If Ruff is configured (any `[tool.ruff]` in `pyproject.toml`, a `ruff.toml`/`.ruff.toml`, or `ruff` resolvable), run lint and format-check in JSON where available:

```bash
uv run ruff check . --output-format json        # lint
uv run ruff format --check .                     # format drift (exit code is the signal)
```

Fall back to the project's own lint script if it defines one. Convert each lint diagnostic into a finding:

- `rule_id`: `QUAL.ruff.<upstream-code>` (preserve the upstream code after `QUAL.ruff.`, e.g. `QUAL.ruff.ANN001`).
- `severity`: map Ruff errors → `high`, fixable/style codes → `medium`. (The constitution treats warnings as errors on protected branches; for one audit pass we keep the distinction so the team can triage.)
- `section`: `Code Quality / Lint ground truth`.
- `phase`: `P1`.
- `directive`: "One linter, one formatter: Ruff for both; warnings are errors on protected branches".
- `file`, `line`, `column`, `snippet`, `message`.

Any `ruff format --check` drift becomes one finding under `QUAL.ruff.format-drift` (`high`) listing the files that would reformat. Cap at 500 lint findings total; truncate and warn beyond that.

### 4. Run mypy --strict (Layer 3)

If a `[tool.mypy]` config exists or `mypy` is resolvable, run it strict over the scoped package:

```bash
uv run mypy --strict <paths or package>
```

Prefer the project's own typecheck script (`mypy` invocation in `[tool.*]`, a `Makefile`, or a `typecheck` entry) when defined — it carries the project's real module topology and per-module overrides.

Capture stdout/stderr. If `mypy` is not installed, **report this as a finding** under `TYPE.tooling.missing-mypy` (`critical` — the constitution makes strict typing P1 Critical) rather than failing silently.

Parse each diagnostic into an additional finding under a synthetic rule:

- `rule_id`: `TYPE.mypy.<error-code>` (preserve mypy's bracketed code, e.g. `TYPE.mypy.assignment`, `TYPE.mypy.arg-type`).
- `severity`: `critical` (any `error:` blocks release; `note:` lines attach to their parent error, not standalone findings).
- `section`: `Type Safety / Compiler ground truth`.
- `phase`: `P1`.
- `directive`: "Run mypy --strict over the whole package; type errors fail CI".
- `file`, `line`, `snippet`, plus the original mypy message.

Cap at 200 diagnostics in the report; if more, note the truncation and instruct the user to re-run scoped to a path.

### 5. Run pytest (Layer 4)

If pytest is configured (`[tool.pytest.ini_options]`, `pytest` in a dependency group, or a `tests/` directory), confirm the suite is collectible and green:

```bash
uv run pytest -q --collect-only        # fast: confirms imports + collection succeed
uv run pytest -q                       # quick run when the suite is fast enough
```

Start with `--collect-only` (cheap, catches import/contract drift); escalate to a quick `pytest -q` when the suite is small or the user asked for a full pass. Convert failures:

- A **collection error** → finding under `TEST.pytest.collection-error` (`critical` — a suite that won't import is a red suite).
- A **test failure** → finding under `TEST.pytest.failure` (`critical` — a red suite blocks merge per the constitution).
- `file`, `line` (from the traceback tail), `snippet` (the assertion or error), plus the node id.

If pytest is unavailable, emit one finding under `TEST.tooling.missing-pytest` (`critical`) and continue.

### 6. Dependency vulnerability scan (Layer 5)

If a lockfile (`uv.lock`) or resolved environment is present, run the audit and parse JSON:

```bash
uv run pip-audit --format json          # preferred
# or, when pip-audit is unavailable:
uv pip audit --format json
```

Each vulnerability of `high` or `critical` severity becomes a finding:

- `rule_id`: `SEC.deps.cve-<package>`.
- `severity`: passthrough (`critical`/`high`/`moderate`→`medium`/`low`).
- `section`: `Security / Dependency posture`.
- `phase`: `P3`.
- `directive`: "Pin and vulnerability-scan dependencies; patch CVEs in libraries and the interpreter promptly".
- File: `pyproject.toml` (or `uv.lock`).
- Snippet: short advisory summary, affected version, fixed version, advisory URL.

If neither audit tool is available or no lockfile exists, emit one informational finding under `SEC.deps.no-audit-available` and continue.

### 7. LLM confirmation & cross-file analysis (Layer 6)

This layer is the reason the deep audit exists. The regex pass produces leads; this pass turns leads into verdicts.

For **every Critical finding** and **up to 20 High findings sampled across rules**, do this:

1. **Read the flagged file in full** (or, for large files, ±50 lines around the flagged line).
2. **Confirm or refute** the finding:
   - "Confirmed" if the violation holds in context.
   - "False positive" if context shows the regex was misled (e.g. `any(` the builtin matched as the `Any` type, `# type: ignore` inside a docstring or string literal, an `except Exception` that actually re-raises, an f-string SQL that interpolates a constant identifier, not user data).
   - "Confirmed but mitigated" if surrounding code already neutralizes the risk (e.g. a `subprocess` call whose args are a fixed list with `shell=False`, a `pickle.loads` over bytes the app itself just wrote to a trusted store — note the mitigation and downgrade severity by one step).
3. **Propose a concrete fix** (file path + minimal diff sketch), not just a directive restatement.
4. **Correlate across files**:
   - Group `DATA.os-environ` reads — propose a single PR that routes them all through the typed settings model.
   - For `ERR.bare-except`: list each catch site and propose the narrowest exception plus `raise ... from err` where it re-raises.
   - For `TYPE.any-usage`: list the **top 5 files by `Any` density**; recommend tackling those first.
   - For `SEC.*`: trace each unsafe call to its untrusted input source and propose the parameterized / `safe_load` / arg-list form.

Then verify the architectural invariants the regex pass cannot prove on its own — read across modules:

- **Pure core, imperative shell** — services/domain modules MUST NOT import I/O drivers (DB clients like `psycopg`/`asyncpg`/`sqlalchemy.engine`, HTTP clients like `httpx`/`requests`, filesystem/socket calls). Flag any service that imports a driver directly under `ARCH.io-in-core` (`high`).
- **Boundaries actually parse input** — every external edge (HTTP handler, CLI command, queue consumer, third-party response handler) MUST run its input through a schema (Pydantic / dataclass+validators / attrs) before business logic sees it. A handler that passes a raw `dict`/`str` downstream is `DATA.unparsed-boundary` (`critical`).
- **Settings model owns the environment** — `os.environ` / `os.getenv` MUST appear only inside the typed settings module. Any read elsewhere is `DATA.os-environ` (`critical`), confirmed by reading the file (not just the grep).
- **DIP at the seams** — business logic depends on a `Protocol`/ABC, not a concrete adapter; a service that instantiates a concrete DB/HTTP/clock/RNG inline is `ARCH.concrete-dependency` (`high`).
- **Async hygiene** — for every `async def`, confirm no blocking/sync I/O runs inside it without `asyncio.to_thread`/an executor; flag `CONC.blocking-in-async` (`critical`) when a blocking call sits on the event loop.

For findings minted in this layer, fill the same finding shape (`rule_id`, `severity`, `section`, `phase`, `directive`, `remediation`, `file`, `line`, `snippet`) so they merge cleanly with the script's output.

### 8. Persist the deep audit JSON

Merge all six layers into one document with the same schema as the regex audit, plus a `layers` field describing which layers ran and any that were skipped (with reason).

Write to:

```
.specify/audits/deep/audit-<ISO timestamp YYYYMMDD-HHMMSS>.json
```

Also update `.specify/audits/deep/latest.json`. The deep audit owns `deep/latest.json`; the standard audit owns `.specify/audits/latest.json` — do not touch the latter here.

### 9. Produce the deep report

Output to the user in this exact structure:

```
# Deep Codebase Quality Audit

**Scope**: <paths or "whole repository">
**Files scanned (regex)**: <N>
**Layers run**: regex audit · ruff (<lint count>) · mypy (<diag count>) · pytest (<pass|fail|collected N>) · pip-audit (<vuln count>) · LLM confirmation (<files reviewed>)
**Layers skipped**: <list with reason, or "none">
**Findings**: <total> (critical: <c> · high: <h> · medium: <m> · low: <l>)
**Confirmed**: <c'> · **False positives**: <fp> · **Mitigated**: <m'>
**Persisted**: `.specify/audits/deep/audit-YYYYMMDD-HHMMSS.json` (also `deep/latest.json`)

## Critical, confirmed (block release)

### <rule_id> — <directive>
*Constitution: <section> / <phase> / <criticality> · Scope: <App|Lib|Both>*

- `<file>:<line>` — `<snippet>`
  - **Confirmed**: <one sentence describing why this is real in context>
  - **Fix**: <concrete change, sometimes a minimal diff in fenced code>

### <next rule_id> ...

## High, confirmed

... same shape ...

## False positives (regex misled — no action needed)

### <rule_id> — <reason category>

- `<file>:<line>` — <why this is not a violation>

## Mitigated (do not block, but document)

### <rule_id>

- `<file>:<line>` — <mitigation, e.g. "subprocess args are a fixed list, shell=False">

## Cross-file patterns

- **<pattern name>** affects <N> files across <areas>. Recommended: single PR `<short title>`.
- ...

## Architectural invariants

| Invariant | Status | Evidence |
|---|---|---|
| Pure core, imperative shell (no I/O driver imports in services) | ✓ / ✗ | <files> |
| Boundaries parse input into a typed model | ✓ / ✗ | <files> |
| os.environ only inside the settings model | ✓ / ✗ | <files> |
| DIP — services depend on Protocol/ABC, not concretes | ✓ / ✗ | <files> |
| No blocking I/O on the event loop | ✓ / ✗ / n/a | <files> |

## Toolchain ground truth

- `ruff check`: <clean | N findings>
- `ruff format --check`: <clean | N files drift>
- `mypy --strict`: <clean | N errors>
- `pytest -q`: <green | N failures | collection error>
- `pip-audit`: <clean | N CVEs (critical: c · high: h)>

## Top 5 prioritized actions

1. <action with file paths and rule IDs covered>
2. ...
```

Omit any section that's empty.

### 10. Recommendations

End with a short list:

- If **any** confirmed Critical remains, recommend **not merging** until those are resolved or formally waived.
- If `mypy --strict` is failing, recommend a single typing-tightening PR (no feature work) until mypy is green.
- If `ruff check` is failing on protected branches, recommend wiring `ruff check` + `ruff format --check` into CI as blocking.
- If `pytest` is red or won't collect, recommend fixing the suite before any further audit work — a red suite invalidates every other signal.
- If dependency CVEs exist at Critical/High, recommend treating them as production incidents and bumping/patching promptly.
- Recommend re-running `/speckit-audit-deep` after the next batch of fixes to verify progress.

### 11. Validation before final output

- Every finding listed appears in the persisted JSON.
- No invented findings; every confirmation traces back to a regex/ruff/mypy/pytest/pip-audit diagnostic or a cross-file read that actually happened.
- File paths and lines match what the tools returned (do not normalize them).
- The "False positives" section accounts only for entries the regex pass produced and the LLM confirmed are not violations — never use it to silently drop real findings.
- Layers that were skipped (e.g. no Ruff config, no `uv.lock`, no `tests/`) are listed under "Layers skipped" with a short reason.

## Formatting & Style Requirements

- Use Markdown headings exactly as shown; do not invent new top-level sections.
- Snippets stay on a single line (~200 chars max).
- Wrap rationale and remediation around 100 characters; do not break paths or identifiers.
- Avoid trailing whitespace.
- The report is read by a release reviewer — favor scannable bullets and short tables over paragraphs.

## Post-Execution Hooks

**Check for extension hooks (after deep audit)**:

Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under `hooks.after_audit_deep` first, then `hooks.after_audit`.
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally.
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable.
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation.
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}
    ```
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently.
