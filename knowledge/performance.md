# Performance

Optimization follows measurement: profile to find the real hot path, choose the right data structure, avoid accidental O(n²), stream large data, and cache only deliberately.

## Contents

- Directives — the constitution rows for performance.
- Patterns — profile first, set/dict lookup, `"".join`, streaming generators, deliberate caching.
- Checklist — what a reviewer confirms before merge.

## Directives

| Phase | Crit. | Behavior |
|---|---|---|
| P2 | High | Measure before optimizing: profile (`cProfile`/`py-spy`/`scalene`) to find the real hot path; never guess. |
| P2 | High | Choose the right data structure: `set`/`dict` for membership/lookup, generators for large/streamed sequences, `deque` for queues. |
| P2 | Medium | Avoid accidental O(n²): no repeated `in list` on large data, no string concatenation in loops, no rebuilding immutable structures in a loop. |
| P3 | High | Set explicit timeouts and right-size pools; batch and paginate I/O; avoid N+1 query patterns. |
| P3 | Medium | Stream large datasets rather than loading them whole; bound memory with chunking and generators. |
| P3 | Medium | Cache deliberately (`functools.lru_cache` for pure functions, an external cache for shared state) with a clear invalidation story — never unbounded. |
| P4 | Medium | Track performance budgets (latency P95, throughput, memory) in CI or monitoring; alert on regressions. |

## Patterns

### 1. Profile before optimizing

Find the hot path with data, not intuition.

```python
from __future__ import annotations

import cProfile
import pstats
from collections.abc import Callable


def profile(fn: Callable[[], object]) -> pstats.Stats:
    profiler = cProfile.Profile()
    profiler.enable()
    fn()
    profiler.disable()
    return pstats.Stats(profiler).sort_stats("cumulative")
```

- Do: profile, then optimize the function that actually dominates.
- Don't: micro-optimize a cold path because it "looks slow".

### 2. `set`/`dict` membership over `in list`

Membership against a list is O(n); against a set it is O(1).

```python
from __future__ import annotations

from collections.abc import Iterable


def filter_allowed(items: Iterable[str], allowed: frozenset[str]) -> list[str]:
    return [item for item in items if item in allowed]
```

- Do: test membership against a `frozenset`/`set`.
- Don't: `if item in allowed_list` where `allowed_list` is a large list.

### 3. `"".join` instead of `+=` in a loop

Building a string with `+=` is O(n²); `join` is O(n).

```python
from __future__ import annotations

from collections.abc import Iterable


def render_csv_row(values: Iterable[object]) -> str:
    return ",".join(str(value) for value in values)
```

- Do: collect parts and `"".join(...)` once.
- Don't: `row += str(value) + ","` inside a loop over many values.

### 4. Stream with generators to bound memory

Yield rows instead of materializing a whole list.

```python
from __future__ import annotations

from collections.abc import Iterator
from pathlib import Path


def read_lines(path: Path) -> Iterator[str]:
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            yield line.rstrip("\n")
```

- Do: yield lazily so memory stays bounded regardless of file size.
- Don't: `path.read_text().splitlines()` for a multi-gigabyte file.

### 5. Deliberate, bounded caching

Cache a pure function with a bounded `lru_cache`, not an unbounded global dict.

```python
from __future__ import annotations

from functools import lru_cache


@lru_cache(maxsize=1024)
def fibonacci(n: int) -> int:
    if n < 2:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)
```

- Do: bound the cache with `maxsize` on a pure function.
- Don't: accumulate results in a module-level dict that grows without limit.

## Checklist

- [ ] Optimization is justified by a profile, not a guess.
- [ ] Membership and lookup use `set`/`dict`/`frozenset`, not `in list` on large data.
- [ ] No string concatenation in loops; `"".join` is used instead.
- [ ] Large datasets are streamed with generators; memory is bounded by chunking.
- [ ] I/O sets timeouts, uses right-sized pools, batches/paginates, and avoids N+1 queries.
- [ ] Caches are deliberate and bounded with a clear invalidation story.
- [ ] Performance budgets (P95 latency, throughput, memory) are tracked where it matters.
