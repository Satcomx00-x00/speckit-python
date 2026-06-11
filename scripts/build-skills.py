#!/usr/bin/env python3
"""Generate agentskills.io-format skills from the Python preset's command specs.

This makes the repo self-propelled: `presets/python/commands/speckit.*.md` and
`knowledge/*.md` are the single sources of truth, and this script materializes
`skills/speckit-*/SKILL.md` (frontmatter `name` + `description` + body that
references the installed knowledge base). Run it after editing a command or the
knowledge mapping below.

    python3 scripts/build-skills.py            # regenerate skills/
    python3 scripts/build-skills.py --check    # fail if skills/ is stale (CI)

No third-party dependencies — standard library only (Constitution: prefer the
standard library when it suffices).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
COMMANDS_DIR = REPO / "presets" / "python" / "commands"
SKILLS_DIR = REPO / "skills"

# Installed location of the knowledge base in a target project. Skills reference
# this stable project-relative path so links resolve regardless of where the
# skill file itself is installed (.claude/skills, .github/skills, ...).
KB = ".specify/memory/knowledge"
CONSTITUTION = ".specify/memory/constitution.md"

# Command tokens (dot form) -> rewritten to dash form in skill bodies.
_CMD_TOKENS = [
    "constitution.scan",
    "scaffold.module",
    "audit.deep",
    "adr.new",
    "adr.supersede",
    "adr.audit",
    "docs.sync",
    "context.refresh",
    "feature",
    "plan",
    "tasks",
    "audit",
    "help",
    "constitution",
    "specify",
    "clarify",
    "implement",
    "checklist",
    "analyze",
]
_CMD_TOKENS.sort(key=len, reverse=True)

# Per-command: the knowledge files most relevant (loaded on demand) and a
# one-line "use when" trigger appended to the description for discoverability.
_ALL_KB = [
    "type-safety",
    "code-quality",
    "architecture",
    "data-and-boundaries",
    "error-handling",
    "concurrency",
    "security",
    "performance",
    "testing",
    "packaging",
    "observability",
]
KNOWLEDGE_MAP: dict[str, list[str]] = {
    "feature": [
        "type-safety",
        "data-and-boundaries",
        "architecture",
        "error-handling",
        "testing",
        "security",
    ],
    "scaffold.module": ["type-safety", "architecture", "data-and-boundaries", "testing"],
    "plan": ["architecture", "error-handling", "concurrency", "security", "testing", "performance"],
    "tasks": ["type-safety", "architecture", "testing"],
    "audit": _ALL_KB,
    "audit.deep": _ALL_KB,
    "constitution.scan": ["packaging", "code-quality"],
    "adr.new": ["architecture"],
    "adr.supersede": ["architecture"],
    "adr.audit": ["security", "architecture"],
    "docs.sync": ["code-quality"],
    "context.refresh": [],
    "help": [],
}
USE_WHEN: dict[str, str] = {
    "feature": "the user wants to build or scaffold a new Python feature end-to-end",
    "scaffold.module": (
        "the user wants a single typed module (model, repository, service, tests) for one entity"
    ),
    "plan": "the user wants to plan or decompose a Python feature before implementing it",
    "tasks": "the user wants an ordered, checkable task list from a feature plan",
    "audit": "the user wants to check the codebase against the project's Python constitution",
    "audit.deep": (
        "the user wants a deep quality gate (ruff + mypy + pytest + pip-audit) before a release"
    ),
    "constitution.scan": (
        "the user wants to generate or refresh the project's Python constitution from the repo"
    ),
    "adr.new": "the user makes an architectural decision worth recording",
    "adr.supersede": "the user wants to replace an existing Architecture Decision Record",
    "adr.audit": "the user wants to check the code against accepted ADRs",
    "docs.sync": "the user wants to sync AGENTS.md / CLAUDE.md / Copilot / Gemini context files",
    "context.refresh": "a new session starts and needs the one-page project context pack",
    "help": "the user is unsure which spec-kit command to run next",
}

_TITLECASE = {
    "adr": "ADR",
    "api": "API",
    "cli": "CLI",
    "dto": "DTO",
}


def dash(name: str) -> str:
    return name.replace(".", "-")


def parse_front_matter(text: str) -> tuple[str, str]:
    """Return (front_matter_yaml, body). Empty front matter if absent."""
    if not text.startswith("---"):
        return "", text
    end = text.find("\n---", 3)
    if end == -1:
        return "", text
    fm = text[3:end].lstrip("\n")
    body = text[end + 4 :].lstrip("\n")
    return fm, body


def extract_description(fm: str) -> str:
    """Pull the `description:` value from front matter, collapsed to one line."""
    # Supports both inline and YAML block scalar (`>-` / `|`) styles.
    lines = fm.splitlines()
    out: list[str] = []
    capturing = False
    for line in lines:
        m = re.match(r"^description:\s*(.*)$", line)
        if m:
            first = m.group(1).strip()
            if first and first not in {">-", ">", "|", "|-", ">+"}:
                return re.sub(r"\s+", " ", first).strip()
            capturing = True
            continue
        if capturing:
            if re.match(r"^\S", line):  # next top-level key ends the block
                break
            out.append(line.strip())
    return re.sub(r"\s+", " ", " ".join(out)).strip()


def rewrite_commands(body: str) -> str:
    for c in _CMD_TOKENS:
        body = body.replace(f"/speckit.{c}", f"/speckit-{dash(c)}")
        body = re.sub(rf"\bagent:\s*speckit\.{re.escape(c)}\b", f"agent: speckit-{dash(c)}", body)
    return body


def title_for(stem_suffix: str) -> str:
    parts = stem_suffix.split(".")
    words = [_TITLECASE.get(p, p.capitalize()) for p in parts]
    return "Speckit " + " ".join(words)


def knowledge_section(short_name: str) -> str:
    files = KNOWLEDGE_MAP.get(short_name, [])
    lines = [
        "",
        "---",
        "",
        "## Knowledge base",
        "",
        f"The project constitution at `{CONSTITUTION}` is authoritative. For deep,",
        "task-specific guidance (directives + Do/Don't code patterns), load only the",
        "relevant reference file from the installed knowledge base — do not read them all:",
        "",
    ]
    if files:
        for f in files:
            label = f.replace("-", " ").replace("and ", "& ")
            lines.append(f"- **{label}** → `{KB}/{f}.md`")
    else:
        lines.append(f"- Knowledge base index → `{KB}/README.md`")
    lines.append("")
    return "\n".join(lines)


def build_skill(cmd_path: Path) -> tuple[Path, str]:
    text = cmd_path.read_text(encoding="utf-8")
    fm, body = parse_front_matter(text)

    stem = cmd_path.stem  # speckit.adr.new
    short = stem[len("speckit.") :]  # adr.new
    skill_name = "speckit-" + dash(short)  # speckit-adr-new

    desc = extract_description(fm)
    use_when = USE_WHEN.get(short)
    if use_when and "use when" not in desc.lower():
        desc = f"{desc.rstrip('. ')}. Use when {use_when}."
    desc = re.sub(r"\s+", " ", desc).strip()[:1024]

    out_body = rewrite_commands(body)
    title = title_for(short)
    # Emit the description as a JSON string: valid YAML double-quoted scalar that
    # safely handles colons, quotes, and arrows that would break a plain scalar.
    desc_yaml = json.dumps(desc, ensure_ascii=False)
    content = (
        "---\n"
        f"name: {skill_name}\n"
        f"description: {desc_yaml}\n"
        "---\n\n"
        f"# {title}\n\n"
        "> This skill is generated from the Python preset command\n"
        f"> `presets/python/commands/{cmd_path.name}` by `scripts/build-skills.py`.\n"
        "> Edit the command (or the knowledge map in the generator), then regenerate.\n\n"
        f"{out_body.rstrip()}\n"
        f"{knowledge_section(short)}"
    )
    return SKILLS_DIR / skill_name / "SKILL.md", content


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--check", action="store_true", help="exit non-zero if any skill is missing or stale"
    )
    args = ap.parse_args()

    commands = sorted(COMMANDS_DIR.glob("speckit.*.md"))
    if not commands:
        print(f"no command specs found under {COMMANDS_DIR}", file=sys.stderr)
        return 1

    stale: list[str] = []
    written = 0
    for cmd in commands:
        out_path, content = build_skill(cmd)
        existing = out_path.read_text(encoding="utf-8") if out_path.exists() else None
        if existing == content:
            continue
        if args.check:
            stale.append(str(out_path.relative_to(REPO)))
            continue
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(content, encoding="utf-8")
        written += 1
        print(f"wrote {out_path.relative_to(REPO)}")

    if args.check:
        if stale:
            print("STALE skills (run scripts/build-skills.py):", file=sys.stderr)
            for s in stale:
                print(f"  {s}", file=sys.stderr)
            return 1
        print(f"OK — {len(commands)} skills are up to date")
        return 0

    print(f"\nGenerated {written} skill(s); {len(commands)} total under skills/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
