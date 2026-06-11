# Packaging, Tooling & Dependencies

`pyproject.toml` is the single source of metadata, the environment is reproducible from a committed `uv.lock` and a pinned interpreter, and published libraries ship semver + `py.typed`.

## Contents

- Directives — the constitution rows for packaging and tooling.
- Patterns — `pyproject.toml` metadata, dependency groups, pinned interpreter, tool config, `py.typed`.
- Checklist — what a reviewer confirms before merge.

## Directives

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | Single source of project metadata: `pyproject.toml` (PEP 621). No `setup.py`/`setup.cfg` duplication; one build backend. |
| P1 | Critical | Reproducible environments via uv: `uv.lock` committed, interpreter pinned (`.python-version`/`requires-python`), CI installs `uv sync --frozen`. |
| P1 | High | Pin direct dependencies with sensible bounds; keep dev/test/docs deps in dependency groups, not the runtime set. |
| P2 | High | Configure Ruff, mypy, and pytest in `pyproject.toml`; the same commands run locally and in CI. |
| P2 | High | Support the interpreter versions you claim to (test the matrix); don't use features newer than `requires-python` allows. |
| P3 | High | Published packages: semver, a `CHANGELOG`, `py.typed`, a tested build (`uv build`), a verified artifact before publish. |
| P3 | Medium | Audit dependencies on a cadence; remove unused ones; prefer the standard library when it suffices. |

## Patterns

### 1. PEP 621 metadata as the single source

All project metadata lives under `[project]`; there is no `setup.py`.

```toml
[project]
name = "orders"
version = "1.4.0"
requires-python = ">=3.11"
dependencies = [
    "pydantic>=2.6,<3",
    "httpx>=0.27,<0.28",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

- Do: declare name, version, `requires-python`, and bounded deps in `[project]`.
- Don't: split metadata across `setup.py` and `setup.cfg` to drift apart.

### 2. Dependency groups keep dev tools out of runtime

Test and lint tooling belongs in groups, not the runtime dependency set.

```toml
[dependency-groups]
dev = [
    "pytest>=8",
    "mypy>=1.9",
    "ruff>=0.4",
    "pip-audit>=2.7",
]
```

- Do: keep `pytest`/`mypy`/`ruff` in a `dev` group installed only for development.
- Don't: list test frameworks in `[project].dependencies` shipped to consumers.

### 3. Pin the interpreter for reproducibility

A pinned `.python-version` plus a committed `uv.lock` make the environment exact.

```toml
# pyproject.toml
[project]
requires-python = ">=3.11,<3.13"
# .python-version contains a single line, e.g. "3.11", read by uv.
# CI runs: uv sync --frozen   (installs exactly what uv.lock specifies)
```

- Do: pin the interpreter and install `--frozen` in CI.
- Don't: install from floating ranges so two machines resolve different trees.

### 4. Tool config colocated in `pyproject.toml`

One file configures Ruff, mypy, and pytest; local and CI commands match.

```toml
[tool.ruff]
line-length = 88

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B", "SIM", "RUF", "ANN", "PTH", "TID"]

[tool.mypy]
strict = true
warn_unused_ignores = true

[tool.pytest.ini_options]
addopts = "-q"
```

- Do: configure all three tools in `pyproject.toml`; run the same commands everywhere.
- Don't: keep a separate `mypy.ini` that drifts from the CI invocation.

### 5. Libraries ship `py.typed` and semver

A published, typed package marks itself with `py.typed` so consumers get types.

```python
from __future__ import annotations

# src/orders/__init__.py
# A `py.typed` marker file sits alongside this module so mypy treats the
# package as typed for downstream consumers.

__version__ = "1.4.0"  # matches [project].version; bump per semver
```

- Do: include an empty `py.typed` in the package and version with semver.
- Don't: publish a typed library without `py.typed` — consumers see no types.

## Checklist

- [ ] All metadata is in `pyproject.toml`; no `setup.py`/`setup.cfg` duplication.
- [ ] `uv.lock` is committed and the interpreter is pinned; CI runs `uv sync --frozen`.
- [ ] Direct dependencies are bounded; dev/test/docs deps live in dependency groups.
- [ ] Ruff, mypy, and pytest are configured in `pyproject.toml`; local and CI commands match.
- [ ] The supported interpreter matrix is tested; no features newer than `requires-python`.
- [ ] Published packages carry semver, a `CHANGELOG`, `py.typed`, and a verified build.
- [ ] Dependencies are audited on a cadence and unused ones removed.
