# Security

All external input is hostile until parsed; secrets stay out of the repo and logs; and the dangerous primitives (`eval`, `shell=True`, string SQL, `pickle`) are simply not used on untrusted data.

## Contents

- Directives — the constitution rows for security.
- Patterns — parameterized SQL, argument-list subprocess, `secrets`, argon2 hashing, path confinement, TLS + timeouts.
- Checklist — what a reviewer confirms before merge.

## Directives

| Phase | Crit. | Behavior |
|---|---|---|
| P1 | Critical | Secrets live in a secret manager or untracked env — never in repo, source, build args, logs, or tracebacks; scan history and CI. |
| P1 | Critical | Treat all external input as hostile until parsed and narrowed at the boundary. |
| P2 | Critical | No `eval`/`exec`/`compile` on untrusted input. No `subprocess(..., shell=True)` with interpolated values — pass an argument list. |
| P2 | Critical | Parameterized queries everywhere; never build SQL by string concatenation or f-string interpolation of user data. |
| P2 | Critical | No insecure deserialization of untrusted bytes: no `pickle.loads`, no `yaml.load` (use `yaml.safe_load`), no `marshal`. |
| P2 | Critical | Hash passwords with a memory-hard algorithm (argon2/bcrypt/scrypt); never store/log/echo them. Use `secrets` (not `random`) for tokens. |
| P2 | High | Validate and confine untrusted file paths to a base dir; reject traversal. Treat uploads as hostile (check type/size). |
| P2 | High | Set explicit timeouts and verify TLS on every outbound request; never disable certificate verification. |
| P3 | Critical | Apply least privilege to DB roles, API keys, file permissions, and service accounts. |
| P3 | High | Pin dependencies and vulnerability-scan every change (`pip-audit`/`uv` + advisory DB); patch CVEs promptly. |
| P3 | High | Log auth events and admin actions to an append-only audit trail; never log secrets, tokens, or full PII. |

## Patterns

### 1. Parameterized SQL, never string-built

Let the driver bind values so user data can never become SQL.

```python
from __future__ import annotations

from typing import Protocol


class Cursor(Protocol):
    def execute(self, sql: str, params: tuple[object, ...]) -> None: ...


def find_user_by_email(cursor: Cursor, email: str) -> None:
    cursor.execute("SELECT id FROM users WHERE email = %s", (email,))
```

- Do: pass `email` as a bound parameter.
- Don't: `cursor.execute(f"... WHERE email = '{email}'")` — that is injection.

### 2. Subprocess with an argument list

Avoid the shell entirely so interpolation cannot inject commands.

```python
from __future__ import annotations

import subprocess


def archive(source: str, dest: str) -> int:
    result = subprocess.run(
        ["tar", "-czf", dest, source],
        check=True,
        timeout=30,
    )
    return result.returncode
```

- Do: pass a list and let the OS exec the program directly.
- Don't: `subprocess.run(f"tar -czf {dest} {source}", shell=True)`.

### 3. `secrets` for tokens, argon2 for passwords

Use a CSPRNG for tokens and a memory-hard hash for passwords.

```python
from __future__ import annotations

import secrets

from argon2 import PasswordHasher

_hasher = PasswordHasher()


def new_session_token() -> str:
    return secrets.token_urlsafe(32)


def hash_password(plaintext: str) -> str:
    return _hasher.hash(plaintext)
```

- Do: `secrets.token_urlsafe` for tokens; argon2 for passwords.
- Don't: `random.random()` for tokens or store plaintext/hex-of-plaintext passwords.

### 4. Confine untrusted file paths

Resolve and verify the path stays inside the allowed base directory.

```python
from __future__ import annotations

from pathlib import Path


def safe_join(base: Path, untrusted_name: str) -> Path:
    candidate = (base / untrusted_name).resolve()
    base_resolved = base.resolve()
    if not candidate.is_relative_to(base_resolved):
        msg = f"path traversal rejected: {untrusted_name!r}"
        raise ValueError(msg)
    return candidate
```

- Do: `resolve()` then check `is_relative_to(base)` to block `../` traversal.
- Don't: `base / untrusted_name` without confinement.

### 5. Outbound requests: TLS verified, with a timeout

Every external call has a timeout and keeps certificate verification on.

```python
from __future__ import annotations

import httpx


def get_json(url: str) -> object:
    response = httpx.get(url, timeout=5.0, verify=True)
    response.raise_for_status()
    return response.json()
```

- Do: pass `timeout=...` and keep `verify=True`.
- Don't: omit the timeout or set `verify=False` to "make it work".

## Checklist

- [ ] No secrets in source, config, build args, logs, or tracebacks; CI scans for leaks.
- [ ] All SQL is parameterized; no f-string/concatenated queries with user data.
- [ ] No `eval`/`exec`/`compile` on untrusted input; subprocess uses argument lists, never `shell=True`.
- [ ] No `pickle.loads`/`yaml.load`/`marshal` on untrusted bytes; `yaml.safe_load` is used.
- [ ] Passwords are argon2/bcrypt/scrypt; tokens come from `secrets`, never `random`.
- [ ] Untrusted paths are resolved and confined to a base dir; uploads are size/type checked.
- [ ] Every outbound request sets a timeout and verifies TLS.
- [ ] Dependencies are pinned and scanned (`pip-audit`); least privilege applies to roles and keys.
