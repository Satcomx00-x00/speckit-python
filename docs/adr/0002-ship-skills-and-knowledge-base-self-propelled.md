---
id: 0002
title: Ship agent skills and a knowledge base inside the repo, installable via specify
status: accepted
phase: P1
criticality: High
owner: Satcomx00-x00
date: 2026-06-11
commit: c5c9ecc
supersedes: null
superseded_by: null
rfc: null
constitution_refs:
  - QUAL.RUFF.single-linter
  - PKG.PYPROJECT.single-source
tags:
  - meta
  - skills
  - knowledge
  - distribution
audit:
  require:
    - pattern: "name:\\s*speckit-"
      paths: ["skills/**/SKILL.md"]
      message: "Every skill must declare an agentskills name (ADR-0002)"
---

# ADR 0002: Ship agent skills and a knowledge base inside the repo, installable via specify

## Context and Problem Statement

The toolkit started as slash-command prompt files plus a single large
constitution. Two gaps remained for it to be genuinely *self-propelled* — able
to carry its full capability into any target project and install it through the
`specify` CLI:

1. **Skills** — modern AI agents (Claude Code, Copilot, Codex, Gemini) support
   [agentskills.io](https://agentskills.io) `SKILL.md` capabilities that are
   auto-discovered by a `name` + `description`, distinct from slash commands the
   user must invoke explicitly. The toolkit shipped only the command form.
2. **Knowledge** — the constitution is ~290 lines loaded wholesale. Agents need
   *progressive disclosure*: a deep reference layer they load only the relevant
   slice of, per task.

How do we add both **without** duplicating content, and make the whole thing
installable into a target project via the `specify` CLI (with a fallback when
`specify` is absent)?

## Decision Drivers

- Single source of truth — no hand-maintained duplicate command/skill bodies.
- Progressive disclosure — keep per-call context small (Anthropic skill best practice: SKILL.md < 500 lines, references one level deep, reference files cost zero tokens until read).
- Self-contained distribution — the repo carries prebuilt skills + knowledge.
- Installed through the `specify` CLI only, via a one-line `curl … | bash`.
- Multi-agent — the same artifacts serve Claude, Copilot, Codex, Gemini, Cursor.

## Considered Options

1. **Generate skills from commands + ship a split knowledge base + a `specify`-driven installer (one-line `curl … | bash`)**
2. **Author skills by hand alongside commands** (two parallel sources)
3. **Rely solely on `specify init --integration-options="--skills"`** to derive skills at init time

## Decision Outcome

**Chosen option**: "Generate skills from commands + ship a split knowledge base
+ an installer".

- `scripts/build-skills.py` generates `skills/speckit-*/SKILL.md` from
  `presets/python/commands/*.md` — commands stay the single source of truth, and
  each generated skill appends a *Knowledge base* section linking the relevant
  `.specify/memory/knowledge/*.md` files (loaded on demand). A `--check` mode
  fails CI if `skills/` drifts from the commands.
- `knowledge/` holds the constitution split into 11 topic references
  (type-safety, security, testing, …), each with directives + Do/Don't code
  patterns. Skills point to its installed location at
  `.specify/memory/knowledge/`.
- `extension.yml` declares commands, skills, knowledge, and templates so
  `specify extension add` can register the toolkit.
- `install.sh` is the self-propelled installer, driven **exclusively by the
  `specify` CLI**: it ensures `uv` + `specify` are present, obtains the toolkit
  (local checkout or a shallow clone), and installs it with `specify preset add`
  + `specify extension add` (commands + skills + knowledge from `extension.yml`)
  for any of five agents. It is published as a one-line `curl … | bash` command.
- The repo dogfoods itself: `.claude/skills → ../skills` and
  `.specify/memory/knowledge → ../../knowledge` symlinks.

### Confirmation

- `python3 scripts/build-skills.py --check` is green (skills match commands).
- `./install.sh --dry-run` (and the piped `curl … | bash -s -- --dry-run`) prints
  exactly the `specify preset add` / `specify extension add` invocations for both
  the local-checkout and clone code paths; `shellcheck` is clean.
- The `audit:` block on this ADR asserts every `skills/**/SKILL.md` declares a
  `name`.

## Consequences

### Positive

- One edit to a command (or the knowledge map) regenerates the matching skill.
- Agents pull in only the knowledge slice a task needs — small context, high signal.
- The toolkit installs into any project with a single `curl … | bash` line.

### Negative

- `skills/` is generated and committed; contributors must run the generator (CI `--check` guards this).
- Knowledge lives in two conceptual places (constitution = directives, `knowledge/` = deep reference); they must stay consistent.

### Neutral

- Five agent layouts are supported; adding another is a `case` arm in `install.sh`.

## Pros and Cons of the Options

### Generate skills + split knowledge + specify-driven installer

**Pros**: single source of truth; progressive disclosure; one-line `specify` install.
**Cons**: a build step and a committed generated tree; install requires the `specify` CLI (auto-installed via uv).

### Hand-author skills alongside commands

**Pros**: full control over each skill body.
**Cons**: double maintenance; commands and skills drift.

### Rely on `specify --skills` only

**Pros**: zero extra files.
**Cons**: not self-contained; no curated knowledge base; depends on the CLI and its version.

## More Information

- Related ADRs: ADR-0001 (toolchain baseline).
- Build: `scripts/build-skills.py` · Manifest: `extension.yml` · Installer: `install.sh`.
- Constitution sections enforced: Packaging & Tooling (single source), Code Quality.
- Review date: 2027-06-11, or when `specify` gains native skills+knowledge install.
