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
- `specify`-installable, but degrades to a pure file install with no CLI dependency.
- Multi-agent — the same artifacts serve Claude, Copilot, Codex, Gemini, Cursor.

## Considered Options

1. **Generate skills from commands + ship a split knowledge base + an installer that uses `specify` with a file fallback**
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
- `install.sh` is the self-propelled installer: it copies the prebuilt commands,
  skills, knowledge, templates, and scripts into a target project (any of five
  agents), and with `--with-specify` also registers the preset through the CLI.
  It works with **or without** `specify` installed.
- The repo dogfoods itself: `.claude/skills → ../skills` and
  `.specify/memory/knowledge → ../../knowledge` symlinks.

### Confirmation

- `python3 scripts/build-skills.py --check` is green (skills match commands).
- `./install.sh --target <tmp> --dry-run` lists exactly the expected artifacts;
  a real install into a clean directory produces 13 commands, 13 skills, and the
  knowledge base under `.specify/memory/knowledge/`.
- The `audit:` block on this ADR asserts every `skills/**/SKILL.md` declares a
  `name`.

## Consequences

### Positive

- One edit to a command (or the knowledge map) regenerates the matching skill.
- Agents pull in only the knowledge slice a task needs — small context, high signal.
- The toolkit installs into any project, with or without the `specify` CLI.

### Negative

- `skills/` is generated and committed; contributors must run the generator (CI `--check` guards this).
- Knowledge lives in two conceptual places (constitution = directives, `knowledge/` = deep reference); they must stay consistent.

### Neutral

- Five agent layouts are supported; adding another is a `case` arm in `install.sh`.

## Pros and Cons of the Options

### Generate skills + split knowledge + installer

**Pros**: single source of truth; progressive disclosure; CLI-optional install.
**Cons**: a build step and a committed generated tree.

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
