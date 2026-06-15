---
description: List every command in the Python spec-kit preset grouped by phase of use, with one-line descriptions and a state-aware "suggested next" line. Read this when you've forgotten which command to run next, or to onboard a new contributor (human or AI).
---

## User Input

```text
$ARGUMENTS
```

Parse from `$ARGUMENTS`:

| Token | Meaning | Default |
|---|---|---|
| `--phase <p>` | Show only commands for the given phase (`bootstrap` / `planning` / `implementation` / `quality` / `decision-memory`) | all |
| `--format <fmt>` | `human` / `markdown` / `json` | `human` |
| `--detail <level>` | `short` (description only) / `long` (description + flags + handoff chain) | `short` |
| `--installed-only` | Show only commands whose files are present under `.specify/` (omit any registered in `preset.yml` but not installed) | off |

## Pre-Execution Checks

None — `/speckit.help` is a pure read of the preset registry. It must work even when `.specify/` is missing or partially installed.

## Outline

### 1. Locate the preset registry

In order:
1. `.specify/preset.yml` (installed)
2. `presets/python/preset.yml` (in-repo, when run from the spec-kit source tree)
3. Built-in fallback list (the grouped table in step 3)

If none of the above are readable, fall back to the static list in step 3 and label the output `(fallback — preset.yml not found)`.

### 2. Resolve installed status (only if `--installed-only`)

For each command entry, check whether the referenced `file:` path exists relative to `.specify/`. Drop entries whose file is missing.

### 3. Render the grouped command list

Group commands into five phases. The grouping is fixed regardless of preset additions — new commands map to a phase via the `phase:` field in their front-matter, defaulting to `implementation` if absent.

Each command is invokable in two forms:
- **spec-kit form** — `/speckit.<name>` (dot-separated; the canonical form used throughout this preset)
- **Claude Code form** — `/speckit-<name>` (dash form; installed as a Claude Code slash command)

Both forms run the same spec file. The listing below uses the spec-kit form; the dash form is the same name with `.` → `-` (e.g. `/speckit.decision.new` ⇄ `/speckit-decision-new`).

```
# Python spec-kit command reference

Read top to bottom — the phases mirror the order you'll actually run them.
Every command runs as `/speckit.<name>` (spec-kit) or `/speckit-<name>` (Claude Code).

## Bootstrap — project setup (run once per project)

  /speckit.constitution.scan
      Scan the repo (pyproject.toml, tooling config, package layout, docs) and
      emit a Python constitution at .specify/memory/constitution.md with a
      Sync Impact Report mapping evidence to directives. Run first.

  /speckit.docs.sync
      Wire AGENTS.md / CLAUDE.md / .github/copilot-instructions.md / GEMINI.md
      from the agent-context template. Run after constitution changes.

## Planning — per feature

  /speckit.plan <description>
      Decompose a feature into typed contracts, domain models, repository seams,
      pure services, the interface surface, concurrency model, error taxonomy,
      and a testing plan — each item tagged Phase / Criticality.

  /speckit.tasks [plan-path]
      Generate a dependency-ordered implementation task list from a plan, with
      acceptance criteria referencing constitution directives.

## Implementation — per feature

  /speckit.feature <name>
      End-to-end typed feature scaffold: clarify round → contracts → domain
      model → repository Protocol + adapter → Result-returning service →
      interface surface → wiring → pytest. mypy --strict and Ruff clean.

  /speckit.scaffold.module <name>
      Scaffold one typed module (model + repository Protocol + service + tests)
      without the full feature workflow. Reach for it to add a slice.

## Quality — pre-PR / pre-release

  /speckit.audit
      Regex audit against the constitution's directives — type safety, code
      quality, architecture, boundaries, error handling, concurrency, security,
      packaging. Fast; run on every PR.

  /speckit.decision.audit
      Code-vs-ADR audit using each ADR's optional `audit:` block (forbid /
      require / prefer). Honors .specify/waivers.yml. Phase-gated severity.

  /speckit.audit.deep
      Full audit: regex + mypy --strict + ruff check + pip-audit + LLM
      file-level confirmation. Slow; run pre-release.

## Decision memory — capture & carry context

  /speckit.decision.new <title>
      Capture an architectural decision as you make it. MADR 4 (full) format,
      auto-numbered, links the current commit, updates docs/adr/README.md.

  /speckit.decision.supersede <id> <new-title>
      Replace an outdated ADR. Preserves the audit trail and carries
      constitution_refs forward.

  /speckit.context.refresh
      Build .specify/memory/context-pack.md — the one-page snapshot every new
      AI session reads first. Re-run after any ADR / constitution / CHANGELOG
      change.

## Meta

  /speckit.help [--phase <p>] [--detail long]
      This listing.
```

### 4. If `--detail long`, expand each command

For each line, append:
- `Flags:` — pulled from the command file's `User Input` parse table
- `Handoffs:` — pulled from the command's front-matter `handoffs:` block
- `Reads:` — files the command consumes (e.g. `.specify/memory/constitution.md`, `pyproject.toml`)
- `Writes:` — files the command produces (e.g. `docs/adr/`, `tests/<feature>/`)

Skip any field that's empty.

### 5. If `--phase` is set, filter

Show only the matching phase block. Other phases are listed by name with a count, so the reader knows what they're skipping.

### 6. Suggested next command

After the listing, print one line tailored to project state. This is best-effort; skip silently if state can't be read.

| Detected state | Suggestion |
|---|---|
| No `.specify/memory/constitution.md` | `Suggested next: /speckit.constitution.scan` |
| Constitution exists, no `AGENTS.md`/`CLAUDE.md` | `Suggested next: /speckit.docs.sync` |
| Constitution exists, no `specs/*/plan.md` | `Suggested next: /speckit.plan "<feature>"` |
| Plans exist, `docs/adr/` empty | `Suggested next: /speckit.decision.new "..."` to capture in-flight decisions |
| `.specify/memory/context-pack.md` missing or older than newest ADR | `Suggested next: /speckit.context.refresh` |
| Otherwise | `Suggested next: /speckit.audit` (the cheapest signal before any commit) |

## Post-Execution Hooks

None. `/speckit.help` is side-effect free.
</content>
