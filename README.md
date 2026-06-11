<div align="center">

# 🐍 speckit-python

**A state-of-the-art, Spec-Driven Development toolkit specialized for Python.**

Constitution · slash commands · workflows · ADR memory — enforcing
**uv + Ruff + mypy `--strict` + pytest** on every change, for *any* Python
project: web service, CLI, library, data pipeline, or automation.

</div>

---

## What this is

[Spec-Driven Development](https://github.com/github/spec-kit) (SDD) flips the
script on AI coding: instead of prompting an agent and hoping, you give it a
**constitution** (the rules), **commands** (structured workflows), and a
**decision memory** (ADRs + context packs) so every change is planned, typed,
tested, and auditable.

`speckit-python` is the **Python preset** for that system. It ships *behaviors,
not a stack* — it doesn't pick your web framework, ORM, or runtime — but it
encodes, and mechanically enforces, what high-quality Python must do regardless
of those choices.

The non-negotiable toolchain baseline:

| Concern | Tool |
|---|---|
| Environment + locking | **uv** (`uv.lock`, pinned interpreter, `uv sync --frozen`) |
| Lint + format | **Ruff** (one linter, one formatter) |
| Static typing | **mypy `--strict`** (no `Any`, no bare `# type: ignore`) |
| Tests | **pytest** (deterministic, fast, green in CI) |

## The standard, in one breath

Type-safety is a contract · parse-don't-validate at every boundary · pure core,
imperative shell (inject the clock, RNG, DB, logger) · errors are typed and
intentional · security by default (no `eval`, no `shell=True`, no string SQL, no
`pickle`/`yaml.load` of untrusted bytes) · reproducible from a lockfile · tests
are part of the design. The full directive — phased and criticality-tagged —
lives in [`presets/python/templates/constitution-template.md`](./presets/python/templates/constitution-template.md).

## Commands

Installed in `.claude/commands/` as dash-form commands for Claude Code
(`/speckit-feature`), and shipped in `presets/python/commands/` as the portable
spec-kit form (`/speckit.feature`) for other agents.

| Phase of use | Command | What it does |
|---|---|---|
| **Bootstrap** | `/speckit-constitution-scan` | Inventory the repo and export an evidence-mapped Python constitution with a Sync Impact Report |
| | `/speckit-docs-sync` | Sync `AGENTS.md` / `CLAUDE.md` / Copilot / Gemini from the agent-context template |
| **Planning** | `/speckit-plan` | Decompose a feature into layers, data flow, error taxonomy, and a testing plan |
| | `/speckit-tasks` | Turn a plan into a dependency-ordered task list with binary acceptance criteria |
| **Implementation** | `/speckit-feature` | **Scaffold a full typed feature slice — runs a clarification round first** (see below) |
| | `/speckit-scaffold-module` | Scaffold one typed module set (contracts → domain → repo Protocol → service → tests) |
| **Quality** | `/speckit-audit` | Regex audit against the constitution; grouped, prioritized report |
| | `/speckit-audit-deep` | Audit + `ruff` + `mypy --strict` + `pytest` + `pip-audit` + cross-file analysis |
| | `/speckit-adr-audit` | Check the code against accepted ADRs' forbid/require/prefer rules |
| **Decision memory** | `/speckit-adr-new` | Record a decision as a MADR 4 ADR under `docs/adr/` |
| | `/speckit-adr-supersede` | Replace an ADR, preserving the audit trail |
| | `/speckit-context-refresh` | Regenerate the one-page context pack the next session reads first |
| **Help** | `/speckit-help` | List commands grouped by phase with a state-aware "suggested next" |

### ⭐ `/speckit-feature` — clarify, then scaffold

The headline command. Unlike a one-shot scaffolder, it **starts with an
interactive clarification round**: up to five high-impact questions (entity
fields, surface, persistence, async/sync, error style, invariants), each
**led by a recommended default with a one-line reason**, so an ambiguous
one-liner becomes a precise spec *before* a single file is written. Then it
generates a layered, `mypy --strict`-clean slice:

```
contracts.py    → parse-don't-validate input + output DTOs (precise constraints)
models.py       → domain model: branded NewType ids, frozen dataclasses, pure transitions
repository.py   → a Repository Protocol (DIP) + an in-memory adapter
service.py      → pure use cases returning Result[T, E], dependencies injected
{router,cli,tasks}.py → a thin interface surface (API / CLI / library / worker)
tests/…         → deterministic pytest unit tests, zero mocks
```

Every file is typed, Ruff-clean, and traceable to a constitution directive.

## Skills & the knowledge base

The toolkit is **self-propelled** — it carries everything it needs to install itself into another project:

- **Skills** (`skills/speckit-*/SKILL.md`) — [agentskills.io](https://agentskills.io)-format capabilities that agents auto-discover by `name` + `description` (no slash required). They are **generated from the commands** by `scripts/build-skills.py`, so the commands stay the single source of truth (`python3 scripts/build-skills.py --check` guards drift in CI).
- **Knowledge base** (`knowledge/`) — the constitution split into 11 deep-reference topics (`type-safety`, `security`, `testing`, `architecture`, …), each with directives plus Do/Don't code patterns. Every code sample passes `mypy --strict` and `ruff`. Skills link to its installed location (`.specify/memory/knowledge/`) and load **only the slice a task needs** (progressive disclosure — zero context cost until read).

This gives every capability **two surfaces**: an explicit slash command (`/speckit-feature`) and an auto-discovered skill (`speckit-feature`), both backed by the same knowledge base.

## Install into another project (self-propelled)

The repo ships prebuilt artifacts and an installer that works **with or without** the `specify` CLI:

```bash
# Pure file install (no dependency) — pick your agent:
./install.sh --target /path/to/project --agent claude     # or copilot | gemini | codex | cursor

# Preview first:
./install.sh --target /path/to/project --dry-run

# Also register the preset through the spec-kit CLI when it's available:
./install.sh --target /path/to/project --with-specify
```

This deploys the commands, skills, knowledge base, templates, and audit scripts into the target. The toolkit is also declared as a spec-kit extension in `extension.yml` (`specify extension add`) and as a preset in `presets/python/preset.yml` (`specify preset add --dev ./presets/python`).

## Quickstart

```bash
# 1. Reproducible environment (the toolchain the constitution mandates)
uv sync

# 2. In Claude Code, generate this project's phased constitution from real evidence
/speckit-constitution-scan

# 3. Wire the agent context files
/speckit-docs-sync

# 4. Build a feature — answer the clarifying questions, then review the scaffold
/speckit-feature payment_intent --description "Create and capture payment intents"

# 5. Gate it before the PR
/speckit-audit          # constitution rules
/speckit-adr-audit      # decision-specific rules
uv run ruff check && uv run mypy --strict src && uv run pytest
```

## Repository layout

```
.
├── .claude/
│   ├── commands/                # dash-form commands, ready for Claude Code
│   └── skills/  -> ../skills    # dogfood: this repo uses its own skills
├── .specify/memory/
│   ├── constitution.md          # this repo's filled, phased constitution
│   └── knowledge/ -> ../../knowledge   # dogfood: the knowledge base in place
├── skills/                      # agentskills.io SKILL.md (generated from commands)
│   └── speckit-*/SKILL.md
├── knowledge/                   # the knowledge base — 11 deep-reference topics
│   ├── README.md  ·  type-safety.md  ·  security.md  ·  testing.md  · …
├── docs/adr/                    # Architecture Decision Records (MADR 4) + index
├── presets/python/              # the portable Python preset
│   ├── preset.yml               # preset manifest (templates + commands)
│   ├── templates/               # constitution-template.md, agent-context.md
│   ├── commands/                # speckit.*.md command specs (spec-kit form)
│   └── scripts/                 # scan-repo.sh, audit-codebase.sh, SCHEMA.md
├── scripts/build-skills.py      # regenerates skills/ from the commands + knowledge map
├── workflows/python-feature/    # end-to-end feature delivery workflow
├── extension.yml                # spec-kit extension manifest (commands+skills+knowledge)
├── install.sh                   # self-propelled installer (specify-aware, file fallback)
├── pyproject.toml               # canonical uv + Ruff + mypy(strict) + pytest config
├── AGENTS.md  ·  CLAUDE.md      # always-on agent operating rules
└── preset.yml                   # active preset manifest (root)
```

## Adopting the preset in another project

Copy `pyproject.toml`'s `[tool.ruff]`, `[tool.mypy]`, and
`[tool.pytest.ini_options]` blocks, install the commands and templates (via the
`specify` CLI's preset mechanism, or by copying `presets/python/`), then run
`/speckit-constitution-scan` to generate *that* project's own phased,
evidence-mapped constitution. From there, `/speckit-feature` and the audit
commands enforce the standard on every change.

## Governance

The constitution supersedes ad-hoc conventions and AI suggestions. Amendments go
through a PR with a changelog entry; significant decisions are recorded as ADRs;
waivers for Critical/High directives are time-bound with an owner. Drift is
caught on a cadence by `/speckit-audit` and `/speckit-adr-audit`.

## License

MIT.
