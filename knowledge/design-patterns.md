# Design Patterns

The 23 Gang-of-Four patterns rendered in idiomatic, type-safe Python — protocols and dataclasses over Java-style class towers.

## Contents

- [Creational](#creational) — singleton, factory method, abstract factory, builder, prototype.
- [Structural](#structural) — adapter, bridge, composite, decorator, facade, flyweight, proxy.
- [Behavioral](#behavioral) — chain of responsibility, command, iterator, mediator, memento, observer, state, strategy, template method, visitor.

## Creational

Patterns that decouple *what* you create from *how* and *when*. In Python, prefer module-level objects, `functools` caches, and factory functions over ceremony.

### Singleton

**Intent** — Guarantee one shared instance with a single access point.

**Use when** — Exactly one logger, config, or connection pool must exist process-wide.

Pythonic form: a module-level instance is the real idiom; `functools.lru_cache` gives lazy, thread-safe single-instantiation without a metaclass.

```python
from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache


@dataclass(frozen=True)
class AppConfig:
    database_url: str
    max_connections: int


@lru_cache(maxsize=1)
def get_config() -> AppConfig:
    return AppConfig(database_url="postgres://localhost/app", max_connections=10)


print(get_config() is get_config())  # True: same instance, lazily built
```

**Trade-off / avoid when** — It is global mutable state; for testability, inject the dependency instead of reaching for a singleton.

### Factory Method

**Intent** — Defer the choice of concrete class to a creator hook.

**Use when** — The exact product type is decided at runtime by a subclass or caller.

```python
from __future__ import annotations

from typing import Protocol


class Notification(Protocol):
    def send(self, message: str) -> None: ...


class EmailNotification:
    def send(self, message: str) -> None:
        print(f"email: {message}")


class SmsNotification:
    def send(self, message: str) -> None:
        print(f"sms: {message}")


def make_notification(channel: str) -> Notification:
    return EmailNotification() if channel == "email" else SmsNotification()
```

**Trade-off / avoid when** — A plain function or dict dispatch beats a class hierarchy when there is no shared creator behavior to inherit.

### Abstract Factory

**Intent** — Create whole families of related objects without binding to concretes.

**Use when** — Swapping one factory must swap a consistent family (e.g. a cloud-provider product set).

```python
from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


class BlobStore(Protocol):
    def put(self, key: str, data: bytes) -> None: ...


class Queue(Protocol):
    def publish(self, topic: str, body: str) -> None: ...


class CloudFactory(Protocol):
    def store(self) -> BlobStore: ...
    def queue(self) -> Queue: ...


@dataclass(frozen=True)
class App:
    factory: CloudFactory

    def boot(self) -> tuple[BlobStore, Queue]:
        return self.factory.store(), self.factory.queue()
```

**Trade-off / avoid when** — Over-engineering for a single product family; the extra interface layer earns its keep only with two or more families.

### Builder

**Intent** — Assemble a complex object step by step, separate from its representation.

**Use when** — Construction has many optional parts and you want a fluent, validated assembly.

```python
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Self


@dataclass
class ReportBuilder:
    title: str = ""
    sections: list[str] = field(default_factory=list)

    def named(self, title: str) -> Self:
        self.title = title
        return self

    def section(self, text: str) -> Self:
        self.sections.append(text)
        return self

    def build(self) -> str:
        return f"# {self.title}\n" + "\n".join(self.sections)


report = ReportBuilder().named("Q2").section("Revenue up").build()
```

**Trade-off / avoid when** — For a few fields, a `@dataclass` with keyword defaults or keyword-only args is simpler than a builder.

### Prototype

**Intent** — Create new objects by cloning an existing instance.

**Use when** — Construction is expensive and you need many slight variations of a base object.

Pythonic form: `dataclasses.replace` clones a frozen instance with overrides — no hand-written `clone()`.

```python
from __future__ import annotations

from dataclasses import dataclass, replace


@dataclass(frozen=True)
class Shape:
    color: str
    x: int
    y: int


base = Shape(color="red", x=0, y=0)
shifted = replace(base, x=10)  # base is unaffected
print(base.x, shifted.x)  # 0 10
```

**Trade-off / avoid when** — Watch shallow copies of nested mutables; reach for `copy.deepcopy` only when fields are themselves mutable.

## Structural

Patterns that compose objects into larger structures. Python's duck typing and `Protocol` make most of these lighter than their Java originals.

### Adapter

**Intent** — Translate one interface into the one a client expects.

**Use when** — A third-party class you cannot modify has the wrong shape for your code.

```python
from __future__ import annotations

from typing import Protocol


class PaymentGateway(Protocol):
    def charge(self, cents: int) -> bool: ...


class LegacyStripe:
    def make_payment(self, dollars: float) -> dict[str, str]:
        return {"status": "ok", "amount": str(dollars)}


class StripeAdapter:
    def __init__(self, legacy: LegacyStripe) -> None:
        self._legacy = legacy

    def charge(self, cents: int) -> bool:
        result = self._legacy.make_payment(cents / 100)
        return result["status"] == "ok"
```

**Trade-off / avoid when** — If you control both sides, fix the interface directly instead of accreting adapters.

### Bridge

**Intent** — Split an abstraction from its implementation so each varies independently.

**Use when** — Two orthogonal dimensions (e.g. Report × Renderer) would otherwise explode into a class matrix.

```python
from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


class Renderer(Protocol):
    def render(self, body: str) -> str: ...


class HtmlRenderer:
    def render(self, body: str) -> str:
        return f"<p>{body}</p>"


@dataclass(frozen=True)
class Report:
    renderer: Renderer

    def show(self, body: str) -> str:
        return self.renderer.render(body)


print(Report(HtmlRenderer()).show("hello"))
```

**Trade-off / avoid when** — Only one dimension actually varies; then composition without the abstraction split is enough.

### Composite

**Intent** — Treat individual objects and trees of them through one interface.

**Use when** — You model part-whole hierarchies (file systems, UI trees) and operations recurse.

```python
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol


class Entry(Protocol):
    def size(self) -> int: ...


@dataclass(frozen=True)
class File:
    name: str
    bytes_: int

    def size(self) -> int:
        return self.bytes_


@dataclass
class Directory:
    name: str
    children: list[Entry] = field(default_factory=list)

    def size(self) -> int:
        return sum(child.size() for child in self.children)
```

**Trade-off / avoid when** — Leaf and container diverge sharply; forcing one interface then leaks no-op methods.

### Decorator

**Intent** — Add behavior to an object by wrapping it, without subclassing.

**Use when** — Cross-cutting concerns (logging, caching, retry) should stack and compose at runtime.

```python
from __future__ import annotations

from typing import Protocol


class DataSource(Protocol):
    def read(self) -> str: ...


class FileSource:
    def read(self) -> str:
        return "payload"


class UppercaseSource:
    def __init__(self, wrapped: DataSource) -> None:
        self._wrapped = wrapped

    def read(self) -> str:
        return self._wrapped.read().upper()


source: DataSource = UppercaseSource(FileSource())
print(source.read())  # PAYLOAD
```

**Trade-off / avoid when** — For wrapping a single function, `functools.wraps` / a decorator function is the native tool, not a wrapper class.

### Facade

**Intent** — Offer one simple entry point over a complex subsystem.

**Use when** — Clients need a sane default path through many collaborating classes.

```python
from __future__ import annotations


class _Decoder:
    def decode(self, name: str) -> str:
        return f"frames:{name}"


class _Muxer:
    def mux(self, frames: str, fmt: str) -> str:
        return f"{frames}.{fmt}"


class VideoConverter:
    def __init__(self) -> None:
        self._decoder = _Decoder()
        self._muxer = _Muxer()

    def convert(self, name: str, fmt: str) -> str:
        return self._muxer.mux(self._decoder.decode(name), fmt)


print(VideoConverter().convert("cats", "mp4"))
```

**Trade-off / avoid when** — The facade becomes a god-object; keep it thin and leave the subsystem reachable for advanced use.

### Flyweight

**Intent** — Share immutable intrinsic state across many objects to save memory.

**Use when** — You hold millions of near-identical objects and most state is shareable.

Pythonic form: `functools.lru_cache` *is* the flyweight factory cache.

```python
from __future__ import annotations

from dataclasses import dataclass
from functools import cache


@dataclass(frozen=True)
class TreeKind:
    species: str
    texture: str


@cache
def tree_kind(species: str, texture: str) -> TreeKind:
    return TreeKind(species=species, texture=texture)


print(tree_kind("oak", "bark.png") is tree_kind("oak", "bark.png"))  # True
```

**Trade-off / avoid when** — Shared state must be immutable; the optimization is moot unless object count is genuinely large.

### Proxy

**Intent** — Stand in for a real object to control access (cache, lazy-load, guard).

**Use when** — You need caching, access checks, or deferred creation behind the same interface.

```python
from __future__ import annotations

from typing import Protocol


class DataService(Protocol):
    def fetch(self, key: str) -> str: ...


class RealDataService:
    def fetch(self, key: str) -> str:
        return f"data:{key}"  # imagine an expensive query


class CachingProxy:
    def __init__(self, real: DataService) -> None:
        self._real = real
        self._cache: dict[str, str] = {}

    def fetch(self, key: str) -> str:
        if key not in self._cache:
            self._cache[key] = self._real.fetch(key)
        return self._cache[key]
```

**Trade-off / avoid when** — A simple `@functools.cache` on the call covers caching proxies with far less code.

## Behavioral

Patterns about responsibility and communication between objects. Python leans on first-class functions, generators, and typed callbacks here.

### Chain of Responsibility

**Intent** — Pass a request along handlers until one handles it.

**Use when** — Several handlers might process a request (middleware, validation pipelines).

Pythonic form: an ordered list of typed callables, not a linked list of handler classes.

```python
from __future__ import annotations

from collections.abc import Callable, Sequence

Handler = Callable[[int], str | None]


def small(n: int) -> str | None:
    return f"small {n}" if n < 10 else None


def medium(n: int) -> str | None:
    return f"medium {n}" if n < 100 else None


def dispatch(n: int, handlers: Sequence[Handler]) -> str:
    for handle in handlers:
        result = handle(n)
        if result is not None:
            return result
    return f"unhandled {n}"


print(dispatch(50, [small, medium]))  # medium 50
```

**Trade-off / avoid when** — Order is significant and implicit; document it, or a misordered chain silently swallows requests.

### Command

**Intent** — Package a request as an object with `execute`/`undo`.

**Use when** — You need undo/redo, queuing, or transactional batches of operations.

```python
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol


class Command(Protocol):
    def execute(self) -> None: ...
    def undo(self) -> None: ...


@dataclass
class Document:
    text: str = ""


@dataclass
class InsertText:
    doc: Document
    chunk: str

    def execute(self) -> None:
        self.doc.text += self.chunk

    def undo(self) -> None:
        self.doc.text = self.doc.text[: -len(self.chunk)]


@dataclass
class History:
    done: list[Command] = field(default_factory=list)

    def run(self, cmd: Command) -> None:
        cmd.execute()
        self.done.append(cmd)

    def undo(self) -> None:
        if self.done:
            self.done.pop().undo()
```

**Trade-off / avoid when** — A simple callback or `functools.partial` suffices when you do not need `undo` or history.

### Iterator

**Intent** — Traverse a collection without exposing its internal structure.

**Use when** — You want lazy or custom traversal over a container.

Pythonic form: a generator function *is* the iterator — implement `__iter__` with `yield`.

```python
from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass


@dataclass(frozen=True)
class CountUp:
    start: int
    stop: int

    def __iter__(self) -> Iterator[int]:
        current = self.start
        while current <= self.stop:
            yield current
            current += 1


print(list(CountUp(1, 5)))  # [1, 2, 3, 4, 5]
```

**Trade-off / avoid when** — Never hand-roll `__next__`/`StopIteration` when a generator expresses the same traversal in one line.

### Mediator

**Intent** — Route inter-component communication through one coordinator.

**Use when** — Many components interact and direct references create O(n²) coupling.

```python
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field


@dataclass
class Mediator:
    handlers: dict[str, list[Callable[[str], None]]] = field(default_factory=dict)

    def on(self, event: str, handler: Callable[[str], None]) -> None:
        self.handlers.setdefault(event, []).append(handler)

    def notify(self, event: str, payload: str) -> None:
        for handler in self.handlers.get(event, []):
            handler(payload)


hub = Mediator()
hub.on("login", lambda user: print(f"show dashboard for {user}"))
hub.notify("login", "alice")
```

**Trade-off / avoid when** — The mediator itself swells into a god-object; split it once it owns unrelated workflows.

### Memento

**Intent** — Capture and restore an object's state without breaking encapsulation.

**Use when** — You need snapshots for undo, rollback, or checkpoints.

Pythonic form: a `frozen` dataclass is the opaque, immutable memento.

```python
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class EditorMemento:
    content: str


@dataclass
class Editor:
    content: str = ""

    def save(self) -> EditorMemento:
        return EditorMemento(self.content)

    def restore(self, memento: EditorMemento) -> None:
        self.content = memento.content


editor = Editor()
editor.content = "Hello"
snapshot = editor.save()
editor.content = "Hello World"
editor.restore(snapshot)  # back to "Hello"
```

**Trade-off / avoid when** — Snapshots of large state are costly; store deltas instead when memory matters.

### Observer

**Intent** — Notify many dependents automatically when a subject changes.

**Use when** — One change must fan out to an unknown set of listeners (events, reactive UI).

Pythonic form: a typed list of callbacks rather than an `Observer` class hierarchy.

```python
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field

PriceListener = Callable[[int], None]


@dataclass
class StockTicker:
    listeners: list[PriceListener] = field(default_factory=list)

    def subscribe(self, listener: PriceListener) -> None:
        self.listeners.append(listener)

    def set_price(self, price: int) -> None:
        for listener in self.listeners:
            listener(price)


ticker = StockTicker()
ticker.subscribe(lambda p: print(f"alert: {p}"))
ticker.set_price(42)
```

**Trade-off / avoid when** — Unmanaged subscriptions leak; ensure unsubscription, or use weak references for long-lived subjects.

### State

**Intent** — Let an object change behavior when its internal state changes.

**Use when** — Behavior forks on a finite set of states (order lifecycle, connection status).

Pythonic form: an `Enum` plus a transition table keeps a small machine flat and exhaustive.

```python
from __future__ import annotations

from enum import Enum, auto


class Light(Enum):
    RED = auto()
    GREEN = auto()
    YELLOW = auto()


_NEXT: dict[Light, Light] = {
    Light.RED: Light.GREEN,
    Light.GREEN: Light.YELLOW,
    Light.YELLOW: Light.RED,
}


def advance(state: Light) -> Light:
    return _NEXT[state]


print(advance(Light.RED))  # Light.GREEN
```

**Trade-off / avoid when** — States carry rich, divergent behavior; then per-state classes behind a `Protocol` beat a table.

### Strategy

**Intent** — Make a family of algorithms interchangeable at runtime.

**Use when** — A large conditional selects among algorithm variants (pricing, sorting, routing).

Pythonic form: a strategy is just a `Callable` injected as a parameter.

```python
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

PricingStrategy = Callable[[int], int]


def standard(cents: int) -> int:
    return cents


def half_off(cents: int) -> int:
    return cents // 2


@dataclass(frozen=True)
class Checkout:
    pricing: PricingStrategy

    def total(self, cents: int) -> int:
        return self.pricing(cents)


print(Checkout(half_off).total(1000))  # 500
```

**Trade-off / avoid when** — There is exactly one algorithm; an injectable strategy then adds indirection for no payoff.

### Template Method

**Intent** — Fix an algorithm's skeleton; defer specific steps to subclasses.

**Use when** — Several variants share a workflow but differ in a few steps.

```python
from __future__ import annotations

from abc import ABC, abstractmethod


class DataMigration(ABC):
    def run(self) -> str:
        rows = self.read()
        return self.write(rows)

    @abstractmethod
    def read(self) -> list[str]: ...

    @abstractmethod
    def write(self, rows: list[str]) -> str: ...


class CsvMigration(DataMigration):
    def read(self) -> list[str]:
        return ["a", "b"]

    def write(self, rows: list[str]) -> str:
        return f"wrote {len(rows)} rows"


print(CsvMigration().run())  # wrote 2 rows
```

**Trade-off / avoid when** — Inheritance couples steps tightly; passing the variant steps as callables (Strategy) is often more flexible.

### Visitor

**Intent** — Add operations to a stable object structure without editing its classes.

**Use when** — Operations on an AST or shape tree change often while the node types stay fixed.

Pythonic form: `functools.singledispatch` replaces the double-dispatch `accept`/`visit` ceremony.

```python
from __future__ import annotations

from dataclasses import dataclass
from functools import singledispatch
from math import pi


@dataclass(frozen=True)
class Circle:
    radius: float


@dataclass(frozen=True)
class Rectangle:
    width: float
    height: float


@singledispatch
def area(shape: object) -> float:
    raise TypeError(f"no area for {type(shape).__name__}")


@area.register
def _circle_area(shape: Circle) -> float:
    return pi * shape.radius**2


@area.register
def _rectangle_area(shape: Rectangle) -> float:
    return shape.width * shape.height
```

**Trade-off / avoid when** — The node set changes often; visitor makes adding a *type* hard even as it makes adding an *operation* easy.

## Source

Adapted from [Satcomx00-x00/skills-db](https://github.com/Satcomx00-x00/skills-db) (skills/code-quality, MIT); examples ported to Python. For deeper treatment of each pattern, see [refactoring.guru/design-patterns](https://refactoring.guru/design-patterns).
