# scan-repo inventory schema

`scan-repo.sh` emits a JSON document with this top-level shape. The
`schema_version` is bumped when fields are renamed or removed; additive fields
do not bump the version.

```jsonc
{
  "schema_version": "1.0",
  "repo_root": "/abs/path/to/repo",

  "pyproject": {
    "present": true,
    "parser": "tomllib",
    "name": "...", "version": "...",
    "requires_python": ">=3.11",
    "build_backend": "hatchling.build",
    "build_requires": ["hatchling"],
    "scripts": ["mytool"],
    "cli": ["mytool"],
    "dependency_names": ["httpx", "pydantic"],
    "optional_dependency_names": ["pytest"],
    "group_dependency_names": ["mypy", "ruff"],
    "has_project_table": true,
    "tool_tables": ["ruff", "mypy", "pytest"]
  },

  "tooling": {
    "has_uv": true, "has_poetry": false,
    "has_ruff": true, "has_black": false,
    "has_mypy": true, "has_pyright": false,
    "has_pytest": true,
    "has_pydantic": true, "has_attrs": false, "has_sqlalchemy": false,
    "has_fastapi": false, "has_flask": false, "has_django": false,
    "has_litestar": false, "has_typer": false, "has_click": false,
    "has_task_queue": false,
    "has_httpx": true,
    "has_pip_audit": false, "has_hypothesis": false,
    "has_pre_commit": false, "has_tox_nox": false
  },

  "config": {
    "ruff":   { "present": true, "source": "pyproject.toml" },
    "mypy":   { "present": true, "source": "pyproject.toml", "strict": true },
    "pytest": { "present": true, "source": "pyproject.toml" },
    "python_version_file": { "present": true, "value": "3.12" },
    "py_typed_marker": true,
    "uv_lock": true,
    "requirements_files": ["requirements.txt"],
    "setup_py": false,
    "setup_cfg": false,
    "legacy_duplication": false
  },

  "source_layout": {
    "layout": "src",
    "package_names": ["mypkg"],
    "py_file_count": 128,
    "async_def_count": 14,
    "type_ignore_count": 3,
    "bare_except_count": 0
  },

  "testing": { "has_tests_directory": true, "has_conftest": true },

  "git": {
    "is_repo": true,
    "origin_url": "...",
    "default_branch": "main"
  },

  "environment": {
    "env_example_files": [".env.example"],
    "requires_python": ">=3.11"
  },

  "constitution": { "exists": false, "path": ".specify/memory/constitution.md" },

  "markdown": {
    "total": 42,
    "listed": 42,
    "truncated": false,
    "known_docs": ["README.md", "CONTRIBUTING.md"],
    "files": [
      {
        "path": "README.md",
        "size": 1234,
        "headings": [{ "level": 1, "text": "Project" }, { "level": 2, "text": "Setup" }],
        "excerpt": "A short application that ..."
      }
    ]
  }
}
```

## Field semantics

- `pyproject` is parsed with `tomllib` (Python ≥ 3.11) or `tomli` when
  available, falling back to a regex mini-parser (`parser: "regex-fallback"`)
  on older interpreters. `dependency_names` are lowercased PEP 508 names from
  `[project.dependencies]` (and Poetry `[tool.poetry.dependencies]`);
  `optional_dependency_names` and `group_dependency_names` come from
  `[project.optional-dependencies]` and `[dependency-groups]`.
- `pyproject.cli` lists `[project.scripts]` (console entry points) — the same
  keys as `scripts`, surfaced separately as the project's CLI surface.
- `tooling.has_*` flags are **evidence**, not principle requirements. They are
  detected from parsed dependency names, requirements files, raw
  `pyproject.toml` text, and on-disk markers (`uv.lock`, `poetry.lock`,
  `.pre-commit-config.yaml`, `tox.ini`, `noxfile.py`). `has_task_queue` is true
  for any of celery/rq/arq/dramatiq. The constitution stays behavioral; signals
  only inform the Sync Impact Report.
- `config.<tool>.source` records where a config was found: a dedicated file
  (`ruff.toml`, `mypy.ini`, `pytest.ini`), `setup.cfg`/`tox.ini` sections, or a
  `[tool.<x>]` table in `pyproject.toml`. `mypy.strict` is true when any
  detected mypy config sets `strict = true`.
- `config.py_typed_marker` is true when a `py.typed` file exists anywhere in
  the tree (a typed, published package). `config.legacy_duplication` is true
  when `setup.py` or `setup.cfg` coexists with `pyproject.toml`.
- `source_layout.layout` is `"src"` when a top-level `src/` exists, `"flat"`
  when top-level `.py` modules or shallow packages exist, else `"unknown"`.
  `package_names` are directories containing `__init__.py` (test packages
  excluded). The `*_count` fields count line matches across `.py` files,
  excluding noise directories.
- `markdown.files` are sampled from the first `SPECKIT_SCAN_MD_HEAD_BYTES`
  bytes (default 4096) for headings and an excerpt. The full file is **not**
  loaded by the scan; the calling command should `Read` files it needs in full.
- `markdown.truncated` is `true` when `total > SPECKIT_SCAN_MAX_MD_FILES`
  (default 200). The `files` array is capped at that count.

## Excluded directories

Scans prune `.git`, `.venv`, `venv`, `node_modules`, `__pycache__`,
`.mypy_cache`, `.ruff_cache`, `.pytest_cache`, `dist`, `build`, `.tox`, `.nox`,
`.eggs`, and `.specify`.

## Stability

`schema_version: "1.0"` covers the current top-level layout. The script and the
`/speckit.constitution.scan` command are versioned together; if a field is
renamed or removed, the schema version bumps and the command is updated in
lockstep.

---

# audit-codebase inventory schema

`audit-codebase.sh` emits a JSON document with this top-level shape. Companion
commands: `/speckit.audit` and `/speckit.audit.deep`.

```jsonc
{
  "schema_version": "1.0",
  "command": "audit",
  "scanned_at": "2026-06-11T07:42:00Z",
  "repo_root": "/abs/path/to/repo",

  "scope": {
    "files_scanned":  123,
    "paths_included": ["src", "app"],
    "extensions":     [".py", ".pyi"],
    "min_severity":   "low",
    "max_per_rule":   50
  },

  "summary": {
    "rules_evaluated":     21,
    "rules_with_findings": 6,
    "findings_total":      18,
    "by_severity":         { "critical": 4, "high": 7, "medium": 5, "low": 2 },
    "by_section":          { "SEC": 5, "TYPE": 6, "ERR": 4, "QUAL": 3 },
    "by_rule":             { "SEC.EVAL.eval-exec": 1, "TYPE.ANY.any-annotation": 5 }
  },

  "rules": [
    {
      "id":          "SEC.EVAL.eval-exec",
      "severity":    "critical",
      "section":     "Security",
      "phase":       "P2",
      "directive":   "No eval/exec/compile on untrusted input",
      "remediation": "Remove eval()/exec(); parse input into typed structures or dispatch via an explicit mapping."
    }
  ],

  "findings": [
    {
      "rule_id":     "SEC.EVAL.eval-exec",
      "severity":    "critical",
      "section":     "Security",
      "phase":       "P2",
      "directive":   "No eval/exec/compile on untrusted input",
      "remediation": "Remove eval()/exec(); ...",
      "file":        "src/app/handlers.py",
      "line":        42,
      "snippet":     "result = eval(user_supplied_expr)"
    }
  ]
}
```

## Rule ID convention

`<SECTION>.<AREA>.<slug>` where `SECTION` is one of:

| Prefix  | Maps to constitution section                                  |
|---------|---------------------------------------------------------------|
| `TYPE.` | Type Safety & Static Analysis Behaviors                       |
| `QUAL.` | Code Quality & Style Behaviors                                |
| `ARCH.` | Architecture & Design Behaviors                               |
| `DATA.` | Data, Validation & Boundary Behaviors                         |
| `ERR.`  | Error Handling & Resilience Behaviors                         |
| `SEC.`  | Security Behaviors                                            |
| `PERF.` | Performance Behaviors                                         |
| `TEST.` | Testing Behaviors                                             |
| `PKG.`  | Packaging, Tooling & Dependency Behaviors                     |

`AREA` is a short subsection slug (`EVAL`, `SHELL`, `DESER`, `SQL`, `RANDOM`,
`TLS`, `ANY`, `IGNORE`, `CAST`, `EXCEPT`, `PRINT`, `IMPORT`, `OSPATH`, `ENV`,
`IO`, `CONCAT`, `SETUP`, `ASSERTTRUE`, …). `summary.by_section` keys on the
`SECTION` prefix. The full catalog is printable with `--list-rules`.

## Rule catalog

| Rule ID                        | Severity | Section                        | Phase |
|--------------------------------|----------|--------------------------------|-------|
| `SEC.EVAL.eval-exec`           | critical | Security                       | P2    |
| `SEC.SHELL.shell-true`         | critical | Security                       | P2    |
| `SEC.DESER.pickle-loads`       | critical | Security                       | P2    |
| `SEC.DESER.yaml-load`          | critical | Security                       | P2    |
| `SEC.SQL.string-sql`           | high     | Security                       | P2    |
| `SEC.RANDOM.insecure-token`    | medium   | Security                       | P2    |
| `SEC.TLS.verify-false`         | high     | Security                       | P2    |
| `TYPE.ANY.any-annotation`      | high     | Type Safety & Static Analysis  | P1    |
| `TYPE.IGNORE.bare-type-ignore` | high     | Type Safety & Static Analysis  | P1    |
| `TYPE.CAST.cast-usage`         | low      | Type Safety & Static Analysis  | P2    |
| `ERR.EXCEPT.bare-except`       | critical | Error Handling & Resilience    | P1    |
| `ERR.EXCEPT.except-pass`       | high     | Error Handling & Resilience    | P1    |
| `ERR.EXCEPT.broad-except`      | medium   | Error Handling & Resilience    | P2    |
| `QUAL.PRINT.print-debug`       | medium   | Code Quality & Style           | P3    |
| `QUAL.IMPORT.wildcard-import`  | medium   | Code Quality & Style           | P3    |
| `QUAL.OSPATH.os-path`          | low      | Code Quality & Style           | P3    |
| `DATA.ENV.adhoc-environ`       | medium   | Data, Validation & Boundaries  | P2    |
| `ARCH.IO.now-in-logic`         | low      | Architecture & Design          | P1    |
| `PERF.CONCAT.str-concat-loop`  | low      | Performance                    | P2    |
| `PKG.SETUP.legacy-setup`       | low      | Packaging, Tooling & Deps      | P1    |
| `TEST.ASSERTTRUE.assert-true`  | low      | Testing                        | P2    |

Notes on scope and excludes:

- `QUAL.PRINT.print-debug` excludes `cli.py`, `__main__.py`, `__init__.py`, and
  `cli/` paths (where `print` is legitimate output).
- `DATA.ENV.adhoc-environ` excludes `settings.py`/`config.py`/`env.py`/
  `environment.py` and `settings/`/`config/` packages (the validated boundary).
- `ARCH.IO.now-in-logic` and `PERF.CONCAT.str-concat-loop` exclude test files.
- `SEC.DESER.yaml-load` ignores lines that name a `SafeLoader`.
- `ERR.EXCEPT.except-pass` and `PERF.CONCAT.str-concat-loop` use a
  python-backed multiline scanner (they span two lines).

## Severity → constitution criticality

| Severity   | Constitution criticality | Release impact                                                            |
|------------|--------------------------|---------------------------------------------------------------------------|
| `critical` | Critical                 | Blocks release. No exception without a recorded waiver and a fixed expiry. |
| `high`     | High                     | Requires an explicit, time-bound exception approved at review.            |
| `medium`   | Medium                   | Default expectation; deviations are noted and tracked.                    |
| `low`      | Low                      | Recommended; revisit during regular audits.                              |

## Exit codes

| Code | Meaning                                                             |
|------|--------------------------------------------------------------------|
| `0`  | No critical findings (after `--severity`/`--rules`/`--sections`).  |
| `1`  | At least one critical finding was emitted.                         |
| `2`  | Usage error (bad flag or `--severity` value).                      |

## Performance for big codebases

- Single file-enumeration pass; rules grep over the cached list.
- Parallel grep via `xargs -P` (default 4; `--parallel N` or
  `SPECKIT_AUDIT_PARALLEL`).
- `--paths` to narrow scope to specific directories.
- `--rules` and `--sections` to run a subset.
- `--max-findings-per-rule` (default 50; `SPECKIT_AUDIT_MAX_PER_RULE`) to keep
  reports bounded.
- `--severity` to raise the floor.
- Binary/NUL-containing files are skipped by the multiline scanner; the
  line-based scanners rely on `grep` which skips binary matches.

## Stability

`schema_version: "1.0"` covers the audit document layout. If a field is renamed
or removed, the schema version bumps in lockstep with the `/speckit.audit*`
commands.
