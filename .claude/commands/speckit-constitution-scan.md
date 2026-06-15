---
description: Scan the repository (Markdown docs, pyproject.toml, tooling config, src layout, async/typing signals, CI) and export a properly-structured Python project constitution at .specify/memory/constitution.md.
handoffs:
  - label: Refine Constitution Interactively
    agent: speckit-constitution
    prompt: Refine the scanned constitution. Adjust principles, criticality, or phases based on...
  - label: Build a Feature
    agent: speckit-feature
    prompt: Scaffold a typed feature slice consistent with the scanned constitution. I want to build...
  - label: Audit Against the Constitution
    agent: speckit-audit
    prompt: Audit the codebase against the scanned constitution's type-safety, security, and architecture directives.
---

## User Input

```text
$ARGUMENTS
```

You **MAY** consider the user input as additional context (e.g. "treat auth as Critical from P1", "this is a published library not an app", "ratification date 2026-05-18", "force phase P3"). If empty, proceed with sensible defaults inferred from the scan.

## Pre-Execution Checks

**Check for extension hooks (before scan)**:

- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_scan` key.
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

You are producing the project constitution at `.specify/memory/constitution.md` by **scanning the repository for evidence** and then mapping that evidence onto the Python phased / criticality-tagged constitution template.

The template lives in the resolution stack as `constitution-template`. With this preset installed, it resolves to the Python variant under `.specify/presets/python/templates/constitution-template.md`. Use that file as the structural skeleton; do **not** invent new sections or reorder existing ones. The behavior matrices (Type Safety, Code Quality, Architecture, Data/Validation, Error Handling, Concurrency, Security, Performance, Testing, Packaging, Observability) are the **source of truth** — the scan informs the Sync Impact Report, never the matrix wording.

Follow this execution flow exactly:

### 1. Run the scan script

Execute the scan script and capture its JSON output. The script lives under the installed preset's scripts directory; both shell variants accept `--json` (default) and `--text`.

- **POSIX shell**:
  ```bash
  bash .specify/presets/python/scripts/bash/scan-repo.sh --json
  ```
- **PowerShell**:
  ```powershell
  pwsh .specify/presets/python/scripts/powershell/scan-repo.ps1 -Json
  ```

If the preset path is not present (preset was added with a non-default install location), fall back to invoking the file by its location on disk relative to `$REPO_ROOT`. Do not silently skip the scan — if the script cannot be found or fails, stop and tell the user.

The script output conforms to the schema documented in `.specify/presets/python/scripts/SCHEMA.md` (`schema_version: "1.0"`). Treat it as your **inventory** for the rest of this command. Do not run the scan more than once per invocation.

### 2. Read the relevant Markdown evidence

From the scan's `markdown.known_docs` list, read the following when present (in this order):

1. `README.md` — purpose, scope, install/run instructions, deployment or PyPI links.
2. `ARCHITECTURE.md` — architectural intent if it exists.
3. `CONTRIBUTING.md` — workflow norms, branch rules, review rules, declared toolchain.
4. `SECURITY.md` — declared security posture and reporting policy.
5. `AGENTS.md` / `CLAUDE.md` / `.github/copilot-instructions.md` — existing agent directives (will be re-aligned with the new constitution).
6. Up to 10 additional `.md` files from `markdown.files` that look like product/engineering specs (paths under `docs/`, `specs/`, `docs/adr/`, or with headings that match "Architecture", "Design", "Spec", "RFC", "ADR").

Skip files larger than ~50 KB; the scan already gives you size, head excerpt, and headings. Use those summaries when the file is too large to read in full.

### 3. Derive concrete values from the inventory

From `inventory.pyproject`:

- `[PROJECT_NAME]` ← `pyproject.name` if present; otherwise the basename of `repo_root`.
- Capture `version`, `requires_python`, `build_backend`, `dependency_count`, `dependency_group_count`, and `console_scripts` — surface them in the Sync Impact Report but do **not** rewrite principle wording around them (the constitution is behavioral, not stack-locked).
- Use `pyproject.signals` / `inventory.tooling.signals` to decide which **evidence notes** to add to the Sync Impact Report (e.g. "Pydantic detected; parse-don't-validate path available", "FastAPI detected; async boundary recipe applies", "pip-audit configured; CVE scanning path available", "argon2/bcrypt detected; password-hashing path available"). **Do not promote tooling to principles.** Principles stay behavioral.

From `inventory.tooling` (the toolchain baseline is **uv**, **Ruff**, **mypy `--strict`**, **pytest**):

- If `has_mypy === false` **or** the mypy config does not set `strict = true` (no `[tool.mypy] strict` and no equivalent `disallow_untyped_defs` + `warn_unused_ignores` + `no_implicit_optional` cluster), mark the **Type Safety / P1 / Critical** directive "Run `mypy --strict` over the whole package" as **NOT MET**.
- If `has_ruff === false` (no `[tool.ruff]` config and no `ruff` in tooling), mark the **Code Quality / P1 / Critical** directive "One linter, one formatter: Ruff for both" as **NOT MET**. If Ruff is present but the rule set is minimal (no `ANN`/`B`/`SIM`/`RUF` selected), flag the **P1 / High** "strong Ruff rule set" directive as **PARTIAL**.
- If `has_pytest === false` (no `[tool.pytest.ini_options]`, no `pytest` in a dependency group, no `tests/` directory), mark the **Testing / P1 / Critical** directive "Tests run under pytest and pass in CI" as **NOT MET** (or **UNVERIFIED** if a test directory exists but no runner is configured).
- If `has_uv === false` or `uv.lock` is absent, mark the **Packaging / P1 / Critical** directive "Reproducible environments via uv: `uv.lock` committed" as **NOT MET**. If a lockfile exists but no pinned interpreter (`.python-version` absent **and** `requires_python` null), mark it **PARTIAL**.

From `inventory.layout`:

- If `src_layout === false` and `flat_layout === true`, add a Sync Impact Report note: "Flat layout detected; constitution examples assume `src/<pkg>`. Not a violation — record the chosen layout so scaffolds match it."
- If `has_py_typed === false` and the project is a publishable package (build backend present, `console_scripts` empty or library-shaped), flag the **Type Safety / P3 / Medium** directive "Ship `py.typed`" as **NOT MET** and the **Packaging / P3 / High** published-package directive as **PARTIAL**.

From `inventory.signals` (raw counts the scan greps):

- `type_ignore_count` (bare `# type: ignore` without a code) → if `> 0`, flag the **Type Safety / P1 / High** directive "Ban bare `# type: ignore`" as **NOT MET** with the count as evidence.
- `bare_except_count` (`except:` and `except Exception: pass`) → if `> 0`, flag the **Error Handling / P1 / Critical** directive "Ban bare `except:`" as **NOT MET**.
- `async_def_count` → if `> 0`, the **Concurrency & Async** section applies as written; note it. If `0`, mark async directives **UNVERIFIED** (no async surface to judge).
- `os_environ_count` (direct `os.environ[...]` reads outside a settings module) → if `> 0`, flag the **Data/Validation / P2 / Critical** directive "Validate configuration at startup with a typed settings model; never read `os.environ` ad-hoc" as **NOT MET**.

From `inventory.tooling.ci_workflows` and `inventory.git`:

- Missing CI workflows → flag the **Observability / P2 / High** directive "CI runs format-check, lint, typecheck, and tests on every PR" as **NOT MET**.
- Missing `pip-audit` / `uv pip audit` step in CI when dependencies exist → note as a Medium gap (**Security / P3 / High** "vulnerability-scan every change" → **PARTIAL**).

### 4. Decide the operating phase

If `inventory.constitution.exists === false` and no production deployment or published-release evidence is found in scanned docs, default to **P1 — Foundation** as the current phase. Otherwise infer the phase from evidence:

- Mentions of "paying customers", "production users", "SLA", "PCI/HIPAA/SOC2" in scanned docs → **P3 — Hardening** at minimum.
- A live production URL in `README.md`, a deploy workflow, **or** a published PyPI release (version on PyPI, `uv build`/`twine` in CI) → **P2 — MVP** at minimum.
- Otherwise → **P1 — Foundation**.

Record the chosen phase, the evidence trail, and a one-line justification at the top of the Sync Impact Report. If the user input from `$ARGUMENTS` explicitly states a phase, use that and note it as **user-overridden**.

### 5. Draft the constitution

Resolve the Python constitution template:

- Prefer `.specify/presets/python/templates/constitution-template.md`.
- If unavailable, fall back to `.specify/templates/constitution-template.md`.

Fill the template precisely:

- Replace `[PROJECT_NAME]` everywhere.
- Replace `[CONSTITUTION_VERSION]`, `[RATIFICATION_DATE]`, `[LAST_AMENDED_DATE]`:
  - `CONSTITUTION_VERSION`: if no prior constitution, start at `1.0.0`. If amending, bump per the existing rules (MAJOR for principle redefinition, MINOR for additions, PATCH for clarifications).
  - `RATIFICATION_DATE`: if the user provided one, use it. Else use today (ISO `YYYY-MM-DD`) and note "first ratification by scan."
  - `LAST_AMENDED_DATE`: today.
- **Do not rewrite the behavior matrices** (Type Safety, Code Quality, Architecture, Data/Validation, Error Handling, Concurrency, Security, Performance, Testing, Packaging, Observability). They are the source of truth. The scan informs the Sync Impact Report, not the matrix.
- **Do not add technology names to the Core Principles section.** The constitution stays behavioral; uv/Ruff/mypy/pytest are referenced by capability in the template, not added as new principles.

### 6. Produce the Sync Impact Report

Prepend an HTML comment block at the top of the constitution containing:

```
<!--
Sync Impact Report — generated by /speckit-constitution-scan
-----------------------------------------------------------
Scan timestamp:       <ISO UTC>
Schema version:       <inventory.schema_version>
Repo root:            <inventory.repo_root>
Chosen phase:         P1 | P2 | P3 | P4   (justification: ...)
Constitution version: <old> → <new>   (bump rationale: ...)
Ratification date:    <ISO>
Last amended date:    <ISO>

## Inventory snapshot
- Project name:        ...
- Project kind:        app | library | cli | data-pipeline | unknown
- Build backend:       ...
- requires-python:     ...
- Interpreter pinned:  <.python-version | requires-python | "no">
- uv.lock present:     true|false
- Source layout:       src | flat
- py.typed shipped:    true|false
- Ruff configured:     true|false  (rule set: <selected groups or "minimal">)
- mypy strict:         true|false
- pytest configured:   true|false  (tests dir: true|false)
- pip-audit / uv audit: true|false
- Pydantic / attrs:    ...
- Web/CLI/worker dep:  <fastapi|flask|django|typer|click|celery|... or "none">
- async def count:     <n>
- bare # type: ignore: <n>
- bare except count:   <n>
- os.environ reads:    <n> (outside settings)
- CI workflows:        <count>
- Constitution found:  true|false
- Markdown files:      <total> (listed <n>, truncated <bool>)

## Directive compliance (from scan)
- [Type Safety / P1 / Critical] mypy --strict over the whole package — <MET|NOT MET|UNVERIFIED> (<evidence>)
- [Type Safety / P1 / High] No bare `# type: ignore` — <MET|NOT MET> (<count>)
- [Code Quality / P1 / Critical] One linter+formatter: Ruff — <MET|NOT MET> (<evidence>)
- [Code Quality / P1 / High] Strong Ruff rule set — <MET|PARTIAL|NOT MET> (<evidence>)
- [Architecture / P1 / Critical] Pure core, imperative shell — <MET|UNVERIFIED|NOT MET> (<evidence: greps for I/O in services>)
- [Data/Validation / P2 / Critical] Typed settings model; no ad-hoc os.environ — <MET|NOT MET> (<count>)
- [Error Handling / P1 / Critical] No bare `except:` — <MET|NOT MET> (<count>)
- [Concurrency / P2 / Critical] Don't block the event loop — <MET|UNVERIFIED> (<async def count>)
- [Security / P1 / Critical] Secrets never in repo/source/logs — <MET|UNVERIFIED|NOT MET> (<evidence>)
- [Security / P3 / High] Pin + vulnerability-scan dependencies — <MET|PARTIAL|NOT MET> (<evidence>)
- [Testing / P1 / Critical] Tests run under pytest in CI — <MET|NOT MET|UNVERIFIED> (<evidence>)
- [Packaging / P1 / Critical] Reproducible env via uv; uv.lock committed; interpreter pinned — <MET|PARTIAL|NOT MET> (<evidence>)
- [Packaging / P1 / Critical] Single pyproject.toml metadata source — <MET|NOT MET> (<setup.py/cfg present?>)
- [Observability / P2 / High] CI runs format/lint/typecheck/test — <MET|NOT MET> (<evidence>)
- ... include every Critical P1 directive at minimum; add Highs when evidence speaks to them.

## Markdown evidence consulted
- README.md (...)
- ARCHITECTURE.md (...)
- ...

## Templates requiring updates
- ✅ <path> — aligned
- ⚠ <path> — references a contradicting assumption: <what>

## Follow-ups (TODO)
- TODO(<area>): <action>, owner=<unknown>, due=<next release>
-->
```

A directive's status is one of:

- **MET** — direct evidence in the scan supports it.
- **NOT MET** — direct evidence shows it is violated or missing.
- **PARTIAL** — some but not all sub-criteria are evidenced.
- **UNVERIFIED** — no signal either way; mark for follow-up.

Always emit a status for every **Critical** directive in P1 and any phase up to the chosen phase. Highs are listed when the scan speaks to them.

### 7. Consistency propagation

After writing the constitution:

- Read `.specify/templates/plan-template.md`, `.specify/templates/spec-template.md`, `.specify/templates/tasks-template.md`, and every command file under `.specify/templates/commands/*.md` (and the preset's command files). If any reference principles that contradict this constitution (e.g. assume a flat layout when the repo is `src/`, ignore the typed settings model, treat `Any` as acceptable, skip the lockfile), flag them in the Sync Impact Report under **Templates requiring updates** with ✅/⚠ markers — do not silently edit them.
- Read `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md` (whichever exist) and confirm they point at `.specify/memory/constitution.md` and (if available) `.specify/presets/python/templates/agent-context.md`. If they don't, flag a follow-up to wire them — do not auto-rewrite the agent context here.

### 8. Validation before write

Before overwriting `.specify/memory/constitution.md`:

- No remaining unexplained `[BRACKET]` tokens.
- Version line matches the Sync Impact Report.
- Dates in ISO `YYYY-MM-DD` format.
- Principle wording is declarative ("MUST", "SHALL"), not vague ("should consider").
- Every Critical directive has a status in the Sync Impact Report.

If `.specify/memory/` does not exist, create it.

### 9. Write the constitution

Write the completed file to `.specify/memory/constitution.md` (overwrite if present).

### 10. Output summary

Print to the user:

- New version and bump rationale (or `1.0.0` if first ratification).
- Chosen operating phase and justification.
- Count of Critical directives **MET / NOT MET / PARTIAL / UNVERIFIED**.
- A 3–7 line summary of the most urgent follow-ups (P1 Critical "NOT MET" first — e.g. "no `uv.lock`", "mypy not strict", "Ruff not configured", "tests not under pytest").
- The exact path to the written file: `.specify/memory/constitution.md`.
- A suggested commit message, e.g.:
  `docs(constitution): scan-derived ratification v1.0.0 — phase P1, <n> directives MET, <m> NOT MET`

## Formatting & Style Requirements

- Use Markdown headings exactly as in the Python constitution template (do not demote/promote levels).
- Keep a single blank line between sections.
- Wrap rationale lines around 100 characters where readable; do not hard-break sentences awkwardly.
- Avoid trailing whitespace.
- The Sync Impact Report is an HTML comment — keep its content scannable; bullets over paragraphs.

## Post-Execution Hooks

**Check for extension hooks (after scan)**:

Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.after_scan` key.
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
