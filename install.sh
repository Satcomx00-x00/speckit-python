#!/usr/bin/env bash
#
# install.sh — self-propelled installer for the Python Spec Kit, driven entirely
# by the spec-kit `specify` CLI.
#
# It (1) ensures `uv` and `specify` are installed, (2) obtains this toolkit
# (the local checkout when run from the repo, otherwise a shallow clone), and
# (3) installs it into a target project using ONLY `specify` subcommands —
# `specify preset add` (constitution template + commands) and
# `specify extension add` (commands + skills + knowledge base from extension.yml).
#
# One-line install (executes this script straight from the download):
#
#   curl -fsSL https://raw.githubusercontent.com/Satcomx00-x00/speckit-python/main/install.sh | bash
#
# With arguments (note the `-s --` to pass flags through the pipe):
#
#   curl -fsSL https://raw.githubusercontent.com/Satcomx00-x00/speckit-python/main/install.sh | bash -s -- --target . --agent claude --skills
#
# Usage (when run directly):
#   ./install.sh [--target DIR] [--agent AGENT] [--skills] [--dry-run]
#
#   --target DIR   Project to install into (default: current directory)
#   --agent AGENT  specify integration: claude | copilot | gemini | codex | cursor (default: claude)
#   --skills       Install agent skills (specify --skills mode) instead of prompt files
#   --dry-run      Print the specify commands without running them
#   -h, --help     Show this help
#
# Environment overrides:
#   SPECKIT_REPO   Git URL of this toolkit  (default: https://github.com/Satcomx00-x00/speckit-python.git)
#   SPECKIT_REF    Branch/tag/commit to clone (default: main)
#
set -euo pipefail

TARGET="$(pwd)"
AGENT="claude"
SKILLS=0
DRY_RUN=0
SPECKIT_REPO="${SPECKIT_REPO:-https://github.com/Satcomx00-x00/speckit-python.git}"
SPECKIT_REF="${SPECKIT_REF:-main}"

log()  { printf '  %s\n' "$*"; }
info() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '20,31p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//'; }

# run <cmd...> — echo and execute, honoring --dry-run.
run() {
    printf '\033[2m$ %s\033[0m\n' "$*"
    [[ $DRY_RUN -eq 1 ]] && return 0
    "$@"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)  TARGET="${2:?}"; shift 2 ;;
        --agent)   AGENT="${2:?}"; shift 2 ;;
        --skills)  SKILLS=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *)         die "unknown argument: $1 (try --help)" ;;
    esac
done

case "$AGENT" in
    claude|copilot|gemini|codex|cursor) ;;
    *) die "unsupported agent: $AGENT (claude|copilot|gemini|codex|cursor)" ;;
esac
[[ -d "$TARGET" ]] || die "target directory does not exist: $TARGET"

# ── 1. Ensure uv ──────────────────────────────────────────────────────────────
ensure_uv() {
    if command -v uv >/dev/null 2>&1; then return 0; fi
    [[ $DRY_RUN -eq 1 ]] && { warn "uv not found — would install it"; return 0; }
    info "Installing uv (required to install the specify CLI)"
    run sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    # uv installs to ~/.local/bin or ~/.cargo/bin; make it visible for this run.
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    command -v uv >/dev/null 2>&1 || die "uv installation did not land on PATH; restart your shell and re-run"
}

# ── 2. Ensure the spec-kit `specify` CLI ──────────────────────────────────────
ensure_specify() {
    if command -v specify >/dev/null 2>&1; then return 0; fi
    [[ $DRY_RUN -eq 1 ]] && { warn "specify not found — would install it via uv"; return 0; }
    info "Installing the spec-kit CLI (specify) via uv"
    run uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
    export PATH="$HOME/.local/bin:$PATH"
    command -v specify >/dev/null 2>&1 || [[ $DRY_RUN -eq 1 ]] \
        || die "specify not found after install; ensure 'uv tool' bin dir is on PATH (uv tool update-shell)"
}

# ── 3. Obtain the toolkit source ──────────────────────────────────────────────
# When run from a checkout, use it. When piped from curl, clone a shallow copy.
resolve_src() {
    local here=""
    if [[ -n "${BASH_SOURCE[0]:-}" && -f "$(dirname "${BASH_SOURCE[0]}")/extension.yml" ]]; then
        here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        printf '%s' "$here"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)"
    info "Fetching the toolkit ($SPECKIT_REPO @ $SPECKIT_REF)" >&2
    run git clone --depth 1 --branch "$SPECKIT_REF" "$SPECKIT_REPO" "$tmp" >&2
    printf '%s' "$tmp"
}

info "Python Spec Kit — specify-driven install into: $TARGET"
log  "agent: $AGENT   skills: $([[ $SKILLS -eq 1 ]] && echo on || echo off)"
[[ $DRY_RUN -eq 1 ]] && warn "dry-run: commands are printed, not executed"

ensure_uv
ensure_specify
SRC="$(resolve_src)"
[[ $DRY_RUN -eq 1 || -f "$SRC/extension.yml" ]] || die "toolkit source missing extension.yml at $SRC"

# ── 4. Install via specify ────────────────────────────────────────────────────
# Everything below uses ONLY the specify CLI. preset add wires the constitution
# template + commands; extension add wires commands + skills + the knowledge base
# declared in extension.yml.
info "Installing with specify"
cd "$TARGET"

PRESET_FLAGS=()
EXT_FLAGS=()
[[ $SKILLS -eq 1 ]] && { PRESET_FLAGS+=(--skills); EXT_FLAGS+=(--skills); }

run specify preset add --dev "$SRC/presets/python" --ai "$AGENT" "${PRESET_FLAGS[@]}" \
    || warn "specify preset add failed — check 'specify --version' and that this is a spec-kit project (specify init)"

run specify extension add --dev "$SRC" --ai "$AGENT" "${EXT_FLAGS[@]}" \
    || warn "specify extension add failed — your specify version may require 'specify extension add <catalog-id>'; try: specify extension add python"

info "Done."
cat <<EOF

Next steps in $TARGET:
  1. specify check                       # verify the toolkit registered
  2. /speckit-constitution-scan          # generate the project constitution
  3. /speckit-docs-sync                  # sync agent context files
  4. /speckit-feature <name>             # build your first feature

Re-run anywhere with the one-liner:
  curl -fsSL https://raw.githubusercontent.com/Satcomx00-x00/speckit-python/main/install.sh | bash
EOF
