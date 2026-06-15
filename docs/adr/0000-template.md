---
id: 0000
title: <Decision title>
status: proposed   # proposed | accepted | rejected | deprecated | superseded
phase: P1          # P1 | P2 | P3 | P4
criticality: Medium  # Critical | High | Medium | Low
owner: <handle>
date: <YYYY-MM-DD>
commit: <short-sha>
supersedes: null
superseded_by: null
rfc: null
constitution_refs:
  - <directive-id>   # e.g. SEC.SQL.string-sql, TYPE.ANY.any-annotation
tags:
  - <tag>
# Optional: enforce this decision in code via /speckit.decision.audit
# audit:
#   forbid:
#     - pattern: "pickle\\.loads?\\("
#       paths: ["src/**/*.py"]
#       message: "Insecure deserialization forbidden (ADR-0000)"
#   require:
#     - pattern: "from __future__ import annotations"
#       paths: ["src/<pkg>/<layer>/**/*.py"]
#       message: "Annotations import required in this layer (ADR-0000)"
#   prefer:
#     - pattern: "import sqlalchemy"
#       message: "SQLAlchemy is the chosen persistence layer (ADR-0000)"
---

# ADR 0000: <Decision title>

## Context and Problem Statement

<Describe the architectural problem this decision addresses. State the problem
as a question if possible. Include constraints, forces, and the system state
that makes this decision necessary now rather than later.>

## Decision Drivers

- <driver 1 — e.g. type-safety guarantees under mypy --strict>
- <driver 2 — e.g. operational simplicity>
- <driver 3 — e.g. team familiarity>
- <driver 4 — e.g. migration risk>

## Considered Options

1. **<Option A>**
2. **<Option B>**
3. **<Option C>** *(if applicable)*

## Decision Outcome

**Chosen option**: "<Option X>".

**Rationale**: <Why this option beats the alternatives against the drivers
above. Reference any RFC, prototype, benchmark, or prior ADR that informs the
choice.>

### Confirmation

<How will we know this decision was correct? What signal (metric, audit rule,
test, post-incident review) confirms it? Set a review date if applicable.>

## Consequences

### Positive

- <consequence 1>
- <consequence 2>

### Negative

- <consequence 1 — including new risks introduced>
- <consequence 2>

### Neutral

- <new conventions teams must adopt>
- <documentation/training implied>

## Pros and Cons of the Options

### <Option A>

**Pros**:
- <pro>

**Cons**:
- <con>

### <Option B>

**Pros**:
- <pro>

**Cons**:
- <con>

## More Information

- Related ADRs: <links>
- Related RFCs: <links>
- Constitution sections enforced: <list of directive IDs>
- Migration plan: <link, or "n/a">
- Review date: <YYYY-MM-DD, or "n/a">
