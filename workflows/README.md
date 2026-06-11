# Workflows

This directory holds spec-kit workflow definitions for the Python-specialized
toolkit. Workflows are multi-step, resumable pipelines defined in YAML: they
chain `speckit.*` commands, run shell quality gates, branch on inputs, and pause
at human review gates for an end-to-end Spec-Driven Development cycle.

## `python-feature` — Python Feature Delivery Cycle

`python-feature/workflow.yml` drives the full delivery cycle for a
**stack-agnostic** Python project. It works whether the feature ships as an
**API** route, a **CLI** command, a **library** function, or a **worker** task —
no web stack is hardcoded. Every generated layer is `mypy --strict` clean,
Ruff-clean, and checked against the project constitution.

### What it does

```
scope / spec  →  clarify  →  plan  →  tasks  →  scaffold (speckit.feature)
   →  quality gates (uv: ruff + mypy --strict + pytest)  →  audit
   →  record ADR (if a decision was made)  →  ship gate
```

### Step sequence

| Phase | Step | Type | What happens |
|-------|------|------|--------------|
| 0 | `scope` | command (`speckit.constitution.scan`) | Scans the constitution and produces the typed feature scope. |
| 0 | `review-scope` | gate | Human review of the scope (`on_reject: abort`). |
| 1 | `clarify` | command (`speckit.clarify-equivalent`) | Up to 5 high-impact clarifying questions, each with a recommended default. |
| 2 | `plan` | command (`speckit.plan`) | Layered implementation plan (contracts → models → repository → service → surface). |
| 2 | `review-plan` | gate | Human review of the plan (`on_reject: abort`). |
| 3 | `tasks` | command (`speckit.tasks`) | Ordered, verifiable task breakdown. |
| 4 | `scaffold` | command (`speckit.feature`) | Generates the typed slice for the chosen surface. |
| 5 | `quality-gates` | if → shell ×4 + gate | Runs the uv quality gates (only when `run_quality_gates` is true). |
| 6 | `audit` | command (`speckit.audit`) | Audits the slice against type-safety, security, and architecture directives. |
| 7 | `adr` | if → command (`speckit.adr.new`) | Records an ADR (only when `needs_adr` is true). |
| 8 | `ship` | gate | Final pre-ship checklist (`on_reject: abort`). |

### Inputs

| Input | Type | Default | Notes |
|-------|------|---------|-------|
| `feature_name` | string | — (required) | Kebab-case or snake_case slug (e.g. `invoice_export`). |
| `feature_description` | string | — (required) | One-line description of the feature. |
| `integration` | string | `claude` | AI integration to dispatch commands to (claude, copilot, gemini). |
| `surface` | string (enum) | `lib` | `api` · `cli` · `lib` · `worker`. |
| `package_root` | string | `src` | Source package root; quality gates target it. |
| `io_style` | string (enum) | `sync` | `async` or `sync`. |
| `validation_lib` | string (enum) | `pydantic` | Boundary validation: `pydantic` · `dataclass` · `attrs`. |
| `needs_adr` | boolean | `true` | Gates the ADR step. |
| `run_quality_gates` | boolean | `true` | Gates the ruff/mypy/pytest phase. |

### How to run

```bash
# Run the installed workflow
specify workflow run python-feature \
  --input feature_name="invoice_export" \
  --input feature_description="Export invoices as CSV" \
  --input surface="cli"

# Or run directly from the local file
specify workflow run ./workflows/python-feature/workflow.yml \
  --input feature_name="invoice_export" \
  --input feature_description="Export invoices as CSV"

# Check status, then resume after approving a gate
specify workflow status
specify workflow resume <run_id>
```

### How the quality gates gate progression

When `run_quality_gates` is true (default), Phase 5 runs four shell steps in
order via **uv**:

```bash
uv run ruff check <package_root>
uv run ruff format --check <package_root>
uv run mypy --strict <package_root>
uv run pytest -q
```

A non-zero exit from any of these fails the step and halts the run; fix the
issue and `specify workflow resume <run_id>` to retry from the failed step.
After the four checks, the `review-quality` gate requires a human approval to
continue — reject to abort. Set `run_quality_gates=false` to skip the entire
phase (e.g. when gates run in CI instead). The terminal `ship` gate then
re-states the same checks as the final pre-ship checklist.

### Requirements

- `speckit_version >= 0.7.2`
- An integration providing the `speckit.*` commands — any of `claude`,
  `copilot`, or `gemini`.
- `uv` available on `PATH` for the quality-gate phase.
