# Concurrency & Async

The event loop is never blocked, every task is owned and awaited, shared state is protected, and concurrency is bounded so the system degrades gracefully.

## Contents

- Directives — the constitution rows for concurrency and async.
- Patterns — offload blocking work, manage tasks, locks/queues, threads vs processes, bounded concurrency.
- Checklist — what a reviewer confirms before merge.

## Directives

| Phase | Crit. | Behavior |
|---|---|---|
| P2 | Critical | Don't block the event loop: never call sync/blocking I/O inside `async def`; offload to a thread/process pool (`asyncio.to_thread`, executors). |
| P2 | High | Don't mix paradigms incoherently: pick async or sync per boundary; don't `asyncio.run` inside a running loop. |
| P2 | High | Await or explicitly manage every coroutine and task; never fire-and-forget without holding a reference and handling exceptions. |
| P3 | High | Protect shared mutable state with the right primitive (`asyncio.Lock`, `threading.Lock`, queues); prefer message passing and immutable data. |
| P3 | Medium | Treat the GIL as real: `multiprocessing`/subprocess for CPU-bound parallelism; threads for I/O-bound concurrency. |
| P3 | Medium | Bound concurrency (semaphores, pool sizes, connection-pool limits) so the system degrades gracefully under load. |

## Patterns

### 1. Offload blocking work to a thread

Keep the loop responsive by moving synchronous I/O off it.

```python
from __future__ import annotations

import asyncio
from pathlib import Path


async def read_blob(path: Path) -> bytes:
    return await asyncio.to_thread(path.read_bytes)
```

- Do: `await asyncio.to_thread(path.read_bytes)` so the loop keeps running.
- Don't: call `path.read_bytes()` directly inside `async def` and stall the loop.

### 2. Own every task; gather results

Hold references and gather so exceptions are not silently dropped.

```python
from __future__ import annotations

import asyncio
from collections.abc import Sequence


async def fetch_one(url: str) -> int:
    await asyncio.sleep(0)  # stand-in for a real awaitable fetch
    return len(url)


async def fetch_all(urls: Sequence[str]) -> list[int]:
    async with asyncio.TaskGroup() as group:
        tasks = [group.create_task(fetch_one(url)) for url in urls]
    return [task.result() for task in tasks]
```

- Do: create tasks inside a `TaskGroup`; failures propagate, none are orphaned.
- Don't: `asyncio.create_task(fetch_one(u))` with no reference and no error handling.

### 3. Protect shared state with a lock

Serialize access to mutable state shared across tasks.

```python
from __future__ import annotations

import asyncio


class Counter:
    def __init__(self) -> None:
        self._value = 0
        self._lock = asyncio.Lock()

    async def increment(self) -> int:
        async with self._lock:
            self._value += 1
            return self._value
```

- Do: guard the read-modify-write with an `asyncio.Lock`.
- Don't: mutate `self._value` from multiple tasks without synchronization.

### 4. Bound concurrency with a semaphore

Cap in-flight work so a burst cannot exhaust connections or memory.

```python
from __future__ import annotations

import asyncio
from collections.abc import Sequence


async def _fetch(url: str, *, gate: asyncio.Semaphore) -> int:
    async with gate:
        await asyncio.sleep(0)
        return len(url)


async def fetch_bounded(urls: Sequence[str], *, limit: int) -> list[int]:
    gate = asyncio.Semaphore(limit)
    async with asyncio.TaskGroup() as group:
        tasks = [group.create_task(_fetch(url, gate=gate)) for url in urls]
    return [task.result() for task in tasks]
```

- Do: acquire a `Semaphore(limit)` so at most `limit` requests run at once.
- Don't: launch one task per item unbounded against a fixed-size pool.

### 5. Processes for CPU-bound work

The GIL serializes CPU-bound threads; use a process pool instead.

```python
from __future__ import annotations

from concurrent.futures import ProcessPoolExecutor


def _sum_squares(n: int) -> int:
    return sum(i * i for i in range(n))


def parallel_sums(sizes: list[int]) -> list[int]:
    with ProcessPoolExecutor() as pool:
        return list(pool.map(_sum_squares, sizes))
```

- Do: use a `ProcessPoolExecutor` for CPU-bound parallelism.
- Don't: spawn threads for CPU work and expect a speedup — the GIL prevents it.

## Checklist

- [ ] No blocking/sync I/O is called inside `async def`; blocking work is offloaded.
- [ ] No `asyncio.run` inside an already-running loop; one paradigm per boundary.
- [ ] Every task is owned (e.g. via `TaskGroup`); exceptions are handled, none orphaned.
- [ ] Shared mutable state is guarded by the right lock or routed through a queue.
- [ ] CPU-bound work uses processes; I/O-bound concurrency uses threads/async.
- [ ] Concurrency is bounded with semaphores and pool/connection limits.
- [ ] Immutable data and message passing are preferred over shared mutable state.
