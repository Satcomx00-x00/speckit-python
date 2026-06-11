#!/usr/bin/env bash
#
# install.sh — self-propelled installer for the Python Spec Kit.
#
# Deploys this repo's prebuilt artifacts into a target project:
#   - slash commands  -> <agent>/commands (or .claude/commands)
#   - agent skills    -> <agent>/skills/<id>/SKILL.md  (agentskills.io)
#   - knowledge base  -> <target>/.specify/memory/knowledge/
#   - templates       -> <target>/.specify/templates/  (+ AGENTS.md)
#   - audit scripts   -> <target>/.specify/scripts/bash/
#   - constitution    -> <target>/.specify/memory/constitution-template.md
#
# It uses the `specify` CLI to register the preset when available
# (--with-specify), and otherwise — or in addition — installs everything with a
# pure file copy so the repo is fully self-contained.
#
# Usage:
#   ./install.sh [--target DIR] [--agent AGENT] [--with-specify] [--dry-run] [--force]
#
#   --target DIR     Project to install into (default: current directory)
#   --agent AGENT    claude | copilot | gemini | codex | cursor (default: claude)
#   --with-specify   Also register the preset/extension via the `specify` CLI
#   --dry-run        Print actions without writing
#   --force          Overwrite an existing constitution/AGENTS.md
#   -h, --help       Show this help
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$(pwd)"
AGENT="claude"
WITH_SPECIFY=0
DRY_RUN=0
FORCE=0

log()  { printf '  %s\n' "$*"; }
info() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)       TARGET="${2:?}"; shift 2 ;;
        --agent)        AGENT="${2:?}"; shift 2 ;;
        --with-specify) WITH_SPECIFY=1; shift ;;
        --dry-run)      DRY_RUN=1; shift ;;
        --force)        FORCE=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              die "unknown argument: $1 (try --help)" ;;
    esac
done

[[ -d "$SRC/skills" ]] || die "run scripts/build-skills.py first — skills/ is missing"
[[ -d "$TARGET" ]] || die "target directory does not exist: $TARGET"

# Per-agent destination directories. Command files and skills are plain Markdown;
# only the directory differs between agents.
case "$AGENT" in
    claude)  CMD_DIR=".claude/commands"; SKILL_DIR=".claude/skills" ;;
    copilot) CMD_DIR=".github/prompts";  SKILL_DIR=".github/skills" ;;
    gemini)  CMD_DIR=".gemini/commands"; SKILL_DIR=".gemini/skills" ;;
    codex)   CMD_DIR=".codex/prompts";   SKILL_DIR=".codex/skills" ;;
    cursor)  CMD_DIR=".cursor/commands"; SKILL_DIR=".cursor/skills" ;;
    *)       die "unsupported agent: $AGENT (claude|copilot|gemini|codex|cursor)" ;;
esac

# do_mkdir / do_cp respect --dry-run.
do_mkdir() { [[ $DRY_RUN -eq 1 ]] && { log "mkdir -p $1"; return; }; mkdir -p "$1"; }
do_cp()    { [[ $DRY_RUN -eq 1 ]] && { log "cp $1 -> $2"; return; }; cp "$1" "$2"; }

install_tree() {  # install_tree <src-glob-dir> <dst-dir> <pattern>
    local sdir="$1" ddir="$2" pat="$3" f
    do_mkdir "$ddir"
    shopt -s nullglob
    for f in "$sdir"/$pat; do
        do_cp "$f" "$ddir/$(basename "$f")"
    done
    shopt -u nullglob
}

info "Python Spec Kit — installing into: $TARGET"
log "source : $SRC"
log "agent  : $AGENT  (commands -> $CMD_DIR, skills -> $SKILL_DIR)"
[[ $DRY_RUN -eq 1 ]] && warn "dry-run: no files will be written"

# 1. Slash commands (prebuilt dash-form; the slash names are plain text and
#    valid guidance for every agent).
info "1/6  commands"
install_tree "$SRC/.claude/commands" "$TARGET/$CMD_DIR" "*.md"

# 2. Skills (one directory per skill, each with SKILL.md).
info "2/6  skills"
if [[ $DRY_RUN -eq 1 ]]; then
    log "cp -r $SRC/skills/* -> $TARGET/$SKILL_DIR/"
else
    mkdir -p "$TARGET/$SKILL_DIR"
    cp -R "$SRC"/skills/. "$TARGET/$SKILL_DIR/"
fi

# 3. Knowledge base (progressive-disclosure reference docs).
info "3/6  knowledge base"
install_tree "$SRC/knowledge" "$TARGET/.specify/memory/knowledge" "*.md"

# 4. Templates + AGENTS.md.
info "4/6  templates"
install_tree "$SRC/presets/python/templates" "$TARGET/.specify/templates" "*.md"
if [[ -f "$TARGET/AGENTS.md" && $FORCE -eq 0 ]]; then
    warn "AGENTS.md exists — leaving it (use --force to overwrite)"
else
    do_cp "$SRC/presets/python/templates/agent-context.md" "$TARGET/AGENTS.md"
fi

# 5. Audit/scan scripts.
info "5/6  scripts"
install_tree "$SRC/presets/python/scripts/bash" "$TARGET/.specify/scripts/bash" "*.sh"
if [[ $DRY_RUN -eq 0 ]]; then
    chmod +x "$TARGET"/.specify/scripts/bash/*.sh 2>/dev/null || true
fi

# 6. Constitution template (never clobber an existing, project-specific constitution).
info "6/6  constitution"
do_mkdir "$TARGET/.specify/memory"
do_cp "$SRC/presets/python/templates/constitution-template.md" \
      "$TARGET/.specify/memory/constitution-template.md"
if [[ -f "$TARGET/.specify/memory/constitution.md" && $FORCE -eq 0 ]]; then
    log "constitution.md exists — left untouched"
else
    log "no constitution yet — run /speckit-constitution-scan to generate one"
fi

# Optional: register with the spec-kit CLI.
if [[ $WITH_SPECIFY -eq 1 ]]; then
    info "specify  registering preset/extension"
    if command -v specify >/dev/null 2>&1; then
        ( cd "$TARGET" && specify preset add --dev "$SRC/presets/python" ) \
            || warn "specify preset add failed (continuing — files were copied directly)"
    else
        warn "specify not found on PATH — skipped CLI registration (files were copied directly)"
    fi
fi

info "Done."
cat <<EOF

Next steps in $TARGET:
  1. Review .specify/memory/knowledge/ and .specify/templates/
  2. Generate the project constitution:   /speckit-constitution-scan
  3. Sync agent context files:            /speckit-docs-sync
  4. Build your first feature:            /speckit-feature <name>
EOF
