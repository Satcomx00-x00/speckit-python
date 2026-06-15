# Code Quality & Style

One linter and one formatter (Ruff), precise naming, small single-responsibility functions, and abstractions that earn their cost.

## Contents

- Directives — the constitution rows for quality and style.
- Patterns — guard clauses, keyword-only options objects, `Enum` over boolean flags, Rule of Three, naming.
- Checklist — what a reviewer confirms before merge.

## Directives

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | One linter, one formatter: Ruff for both; `ruff check` / `ruff format --check` in CI; no second formatter. |
| P1 | High | Enable a strong Ruff rule set (`E,F,I,UP,B,SIM,RUF,ANN,PTH,TID`, ...); fix or `# noqa: CODE  # reason` — never blanket-disable. |
| P1 | High | PEP 8 / PEP 257 naming: `snake_case`, `PascalCase`, `SCREAMING_SNAKE_CASE`, `_private`. |
| P2 | High | One reason to change (SRP); short functions, single level of abstraction, low complexity. |
| P2 | High | Early returns over nested `if`/`else`; guard clauses on top, happy path at the bottom. |
| P2 | High | Self-documenting names; no single-letter names outside tight comprehensions; no non-standard abbreviations. |
| P2 | Medium | Boolean parameters are a smell — prefer an `Enum` or split the function; keyword-only args for clarity. |
| P2 | Medium | DRY only after the third repetition (Rule of Three); avoid premature abstraction. KISS / YAGNI. |
| P2 | Medium | Public modules, classes, functions carry docstrings explaining the *why* and contract. |
| P3 | Medium | No dead code, no commented-out blocks, no leftover `print`; use the logger. No wildcard imports. |
| P3 | Low | Prefer `pathlib.Path` over `os.path`; f-strings; comprehensions where clearer. |

## Patterns

### 1. Guard clauses, happy path last

Flatten the pyramid: reject invalid states early, leave the main flow unindented.

```python
from __future__ import annotations

from myapp.domain import Account


def withdraw(account: Account, amount_cents: int) -> int:
    if amount_cents <= 0:
        msg = "amount must be positive"
        raise ValueError(msg)
    if amount_cents > account.balance_cents:
        msg = "insufficient funds"
        raise ValueError(msg)
    return account.balance_cents - amount_cents
```

- Do: return/raise early on each precondition.
- Don't: nest the happy path inside `if valid: if funded: ...`.

### 2. `Enum` instead of a boolean flag

A flag at the call site is unreadable; an `Enum` names intent.

```python
from __future__ import annotations

from enum import Enum


class Sort(Enum):
    ASCENDING = "asc"
    DESCENDING = "desc"


def sorted_amounts(values: list[int], order: Sort) -> list[int]:
    return sorted(values, reverse=order is Sort.DESCENDING)
```

- Do: `sorted_amounts(values, Sort.DESCENDING)` — self-documenting.
- Don't: `sorted_amounts(values, True)` — what does `True` mean here?

### 3. Keyword-only options object

Group related parameters into a frozen dataclass; force keywords for clarity.

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class PageRequest:
    offset: int
    limit: int


def fetch_page(rows: list[str], *, page: PageRequest) -> list[str]:
    return rows[page.offset : page.offset + page.limit]
```

- Do: `fetch_page(rows, page=PageRequest(offset=0, limit=20))`.
- Don't: `fetch_page(rows, 0, 20)` — positional ints invite transposition bugs.

### 4. Rule of Three before abstracting

Tolerate two near-duplicates; extract only on the third occurrence.

```python
from __future__ import annotations


def normalize_email(raw: str) -> str:
    return raw.strip().lower()


# Reuse this in the third call site; do not pre-build a generic
# "StringNormalizer" framework for two uses.
```

- Do: extract a shared helper once the third caller appears.
- Don't: build a configurable abstraction speculatively for one or two uses.

### 5. Precise names and `pathlib`

Descriptive names plus modern stdlib idioms read better and lint clean.

```python
from __future__ import annotations

from pathlib import Path


def load_report(report_dir: Path, report_id: str) -> str:
    report_path = report_dir / f"{report_id}.txt"
    return report_path.read_text(encoding="utf-8")
```

- Do: `report_path.read_text(...)` with f-strings and clear names.
- Don't: `os.path.join(d, i + ".txt")` with single-letter names.

## Checklist

- [ ] `ruff check` and `ruff format --check` pass; the rule set includes `E,F,I,UP,B,SIM,RUF,ANN,PTH,TID`.
- [ ] Any suppression is `# noqa: CODE  # reason`, never a blanket `# noqa`.
- [ ] Functions are short, single-abstraction, and use guard clauses; complexity stays low.
- [ ] Names are descriptive `snake_case`/`PascalCase`/`SCREAMING_SNAKE_CASE`; no stray single letters.
- [ ] No boolean parameters where an `Enum` or a split function would be clearer.
- [ ] No premature abstraction; duplication is removed only at the third occurrence.
- [ ] No dead code, commented-out blocks, leftover `print`, or wildcard imports.
- [ ] Public APIs carry docstrings explaining the contract and the *why*.

## See also

Deep-dive craft references in this knowledge base:

- [principles.md](principles.md) — SOLID, DRY/KISS/YAGNI, Law of Demeter, CQS, Separation of Concerns, Fail Fast, composition over inheritance.
- [design-patterns.md](design-patterns.md) — the 23 Gang-of-Four patterns in Pythonic form.
- [refactoring.md](refactoring.md) — a catalog of behavior-preserving refactorings (before → after).
