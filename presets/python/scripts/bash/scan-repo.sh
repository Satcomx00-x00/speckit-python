#!/usr/bin/env bash
# scan-repo.sh — scan a Python project repository and emit a structured
# inventory used by /speckit.constitution.scan to draft a properly-structured
# constitution.
#
# Outputs JSON by default; pass --text for a human-readable summary.

set -euo pipefail

JSON_MODE=true
REPO_ROOT_ARG=""
SCAN_MD_HEAD_BYTES="${SPECKIT_SCAN_MD_HEAD_BYTES:-4096}"
MAX_MD_FILES="${SPECKIT_SCAN_MAX_MD_FILES:-200}"

print_help() {
    cat <<EOF
Usage: $0 [--root <path>] [--text] [--json] [--help]

Scans a repository for evidence relevant to a Python project constitution:
Markdown files, pyproject.toml, tooling signals (uv, Ruff, mypy, pytest,
frameworks, ORMs, validators), config presence (Ruff/mypy/pytest configs,
py.typed, lockfiles), source layout, async/type-ignore/bare-except counts,
testing setup, git, and environment files.

Options:
  --root <path>    Root directory to scan (default: auto-detect via
                   .specify, git, or current working directory)
  --json           Emit JSON output (default)
  --text           Emit a human-readable summary instead of JSON
  --help, -h       Show this help and exit

Environment:
  SPECKIT_SCAN_MD_HEAD_BYTES   Bytes of head sampled per .md file (default 4096)
  SPECKIT_SCAN_MAX_MD_FILES    Cap on .md files listed (default 200)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            REPO_ROOT_ARG="$2"; shift 2 ;;
        --json)
            JSON_MODE=true; shift ;;
        --text)
            JSON_MODE=false; shift ;;
        -h|--help)
            print_help; exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2; print_help >&2; exit 2 ;;
    esac
done

# ---------- Resolve repo root --------------------------------------------------

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "$REPO_ROOT_ARG" ]; then
    REPO_ROOT="$(CDPATH="" cd "$REPO_ROOT_ARG" 2>/dev/null && pwd)" || {
        echo "Error: --root path does not exist: $REPO_ROOT_ARG" >&2
        exit 1
    }
elif [ -f "$SCRIPT_DIR/../../../../scripts/bash/common.sh" ]; then
    # Installed under .specify/presets/python/scripts/bash/
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/../../../../scripts/bash/common.sh"
    REPO_ROOT="$(get_repo_root)"
elif command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT="$(git rev-parse --show-toplevel)"
else
    REPO_ROOT="$(pwd)"
fi

cd "$REPO_ROOT"

# ---------- Helpers ------------------------------------------------------------

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# JSON string escape (fallback when python3 is unavailable)
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    printf '%s' "$s"
}

# Common find prune pattern for noise directories
find_prune() {
    find "$1" \
        \( -type d \( \
            -name .git -o \
            -name .venv -o \
            -name venv -o \
            -name node_modules -o \
            -name __pycache__ -o \
            -name .mypy_cache -o \
            -name .ruff_cache -o \
            -name .pytest_cache -o \
            -name dist -o \
            -name build -o \
            -name .tox -o \
            -name .nox -o \
            -name .eggs -o \
            -name .specify \
            \) -prune \) -o \
        "${@:2}" -print 2>/dev/null
}

file_exists_first() {
    # Return first existing file from the argument list, empty if none
    local f
    for f in "$@"; do
        [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

# Grep file contents but never crash; returns 1 (and empty) when no match
grep_files() {
    grep "$@" 2>/dev/null || true
}

# Count matching lines across .py files (excludes noise dirs)
count_py_matches() {
    local pattern="$1"
    { grep -rhE --include='*.py' \
        --exclude-dir=.git --exclude-dir=.venv --exclude-dir=venv \
        --exclude-dir=node_modules --exclude-dir=__pycache__ \
        --exclude-dir=.mypy_cache --exclude-dir=.ruff_cache \
        --exclude-dir=.pytest_cache --exclude-dir=dist --exclude-dir=build \
        --exclude-dir=.tox --exclude-dir=.nox --exclude-dir=.eggs \
        --exclude-dir=.specify \
        "$pattern" . 2>/dev/null || true; } | wc -l | tr -d ' '
}

# ---------- Inventory: pyproject.toml -----------------------------------------

PYPROJECT_PATH=""
PYPROJECT_INVENTORY='{"present": false}'

if [ -f "pyproject.toml" ]; then
    PYPROJECT_PATH="pyproject.toml"
    if has_cmd python3; then
        PYPROJECT_INVENTORY="$(SPECKIT_PYPROJECT="$PYPROJECT_PATH" python3 <<'PY'
import json, os, sys

path = os.environ["SPECKIT_PYPROJECT"]

# tomllib is stdlib >=3.11; fall back to a permissive mini-parser otherwise.
data = None
try:
    import tomllib  # type: ignore
    with open(path, "rb") as f:
        data = tomllib.load(f)
except Exception:
    try:
        import tomli  # type: ignore
        with open(path, "rb") as f:
            data = tomli.load(f)
    except Exception:
        data = None

if data is None:
    # Best-effort regex fallback so we never crash on older interpreters.
    import re
    try:
        raw = open(path, encoding="utf-8").read()
    except Exception as e:
        print(json.dumps({"present": True, "error": f"read failed: {e}"}))
        sys.exit(0)

    def find(pat):
        m = re.search(pat, raw, re.M)
        return m.group(1) if m else None

    result = {
        "present": True,
        "parser": "regex-fallback",
        "name": find(r'^\s*name\s*=\s*["\']([^"\']+)["\']'),
        "version": find(r'^\s*version\s*=\s*["\']([^"\']+)["\']'),
        "requires_python": find(r'^\s*requires-python\s*=\s*["\']([^"\']+)["\']'),
        "build_backend": find(r'^\s*build-backend\s*=\s*["\']([^"\']+)["\']'),
        "scripts": [],
        "dependency_names": [],
        "has_project_table": "[project]" in raw,
    }
    print(json.dumps(result))
    sys.exit(0)

project = data.get("project") or {}
build = data.get("build-system") or {}

def dep_names(deps):
    import re
    names = []
    for d in deps or []:
        if not isinstance(d, str):
            continue
        m = re.match(r"^\s*([A-Za-z0-9_.\-]+)", d)
        if m:
            names.append(m.group(1).lower())
    return names

deps = dep_names(project.get("dependencies"))
optional = project.get("optional-dependencies") or {}
opt_deps = []
for group in optional.values():
    opt_deps.extend(dep_names(group))

# uv / poetry dependency groups may live elsewhere
dep_groups = data.get("dependency-groups") or {}
group_deps = []
for group in dep_groups.values():
    if isinstance(group, list):
        group_deps.extend(dep_names(group))

# Poetry-style
tool = data.get("tool") or {}
poetry = tool.get("poetry") or {}
poetry_deps = []
if isinstance(poetry.get("dependencies"), dict):
    poetry_deps = [k.lower() for k in poetry["dependencies"].keys() if k.lower() != "python"]

scripts = project.get("scripts") or {}
poetry_scripts = poetry.get("scripts") or {}
all_scripts = {}
all_scripts.update(scripts if isinstance(scripts, dict) else {})
all_scripts.update(poetry_scripts if isinstance(poetry_scripts, dict) else {})

result = {
    "present": True,
    "parser": "tomllib",
    "name": project.get("name") or poetry.get("name"),
    "version": project.get("version") or poetry.get("version"),
    "requires_python": project.get("requires-python") or (
        poetry.get("dependencies", {}).get("python") if isinstance(poetry.get("dependencies"), dict) else None
    ),
    "build_backend": build.get("build-backend"),
    "build_requires": build.get("requires") or [],
    "scripts": sorted(all_scripts.keys()),
    "cli": sorted(all_scripts.keys()),
    "dependency_names": sorted(set(deps + poetry_deps)),
    "optional_dependency_names": sorted(set(opt_deps)),
    "group_dependency_names": sorted(set(group_deps)),
    "has_project_table": bool(project),
    "tool_tables": sorted((data.get("tool") or {}).keys()),
}
print(json.dumps(result))
PY
)"
    else
        PYPROJECT_INVENTORY="{\"present\": true, \"warning\": \"python3 unavailable; pyproject.toml not parsed\"}"
    fi
fi

# Extract the merged dependency-name list (lowercased) for signal detection.
DEP_NAMES=""
if has_cmd python3; then
    DEP_NAMES="$(SPECKIT_PI="$PYPROJECT_INVENTORY" python3 -c '
import json, os
try:
    d = json.loads(os.environ.get("SPECKIT_PI") or "{}")
except Exception:
    d = {}
names = set()
for k in ("dependency_names", "optional_dependency_names", "group_dependency_names"):
    for n in d.get(k) or []:
        names.add(str(n).lower())
print("\n".join(sorted(names)))
' 2>/dev/null || true)"
fi

# Detect a dependency name in the parsed pyproject OR in requirements files /
# raw pyproject text (best-effort), so we still catch deps we could not parse.
REQ_TEXT=""
for rf in requirements.txt requirements-dev.txt requirements/dev.txt requirements/base.txt; do
    [ -f "$rf" ] && REQ_TEXT="$REQ_TEXT
$(cat "$rf" 2>/dev/null)"
done
RAW_PYPROJECT=""
[ -f "pyproject.toml" ] && RAW_PYPROJECT="$(cat pyproject.toml 2>/dev/null)"
HAYSTACK="$DEP_NAMES
$REQ_TEXT
$RAW_PYPROJECT"

dep_has() {
    # Case-insensitive whole-word-ish match of a package name.
    printf '%s' "$HAYSTACK" | grep -qiE "(^|[^A-Za-z0-9_.-])$1([^A-Za-z0-9_.-]|$)"
}

bool_of() { if "$@"; then echo true; else echo false; fi; }

HAS_UV="$(bool_of test -f uv.lock)"
if [ -f poetry.lock ] || dep_has 'poetry-core' || dep_has 'poetry'; then HAS_POETRY=true; else HAS_POETRY=false; fi
HAS_RUFF="$(bool_of dep_has 'ruff')"
HAS_BLACK="$(bool_of dep_has 'black')"
HAS_MYPY="$(bool_of dep_has 'mypy')"
HAS_PYRIGHT="$(bool_of dep_has 'pyright')"
HAS_PYTEST="$(bool_of dep_has 'pytest')"
HAS_PYDANTIC="$(bool_of dep_has 'pydantic')"
HAS_ATTRS="$([ "$(bool_of dep_has 'attrs')" = true ] || [ "$(bool_of dep_has 'attr')" = true ] && echo true || echo false)"
HAS_SQLALCHEMY="$(bool_of dep_has 'sqlalchemy')"
HAS_FASTAPI="$(bool_of dep_has 'fastapi')"
HAS_FLASK="$(bool_of dep_has 'flask')"
HAS_DJANGO="$(bool_of dep_has 'django')"
HAS_LITESTAR="$(bool_of dep_has 'litestar')"
HAS_TYPER="$(bool_of dep_has 'typer')"
HAS_CLICK="$(bool_of dep_has 'click')"
HAS_CELERY="$([ "$(bool_of dep_has 'celery')" = true ] || [ "$(bool_of dep_has 'rq')" = true ] || [ "$(bool_of dep_has 'arq')" = true ] || [ "$(bool_of dep_has 'dramatiq')" = true ] && echo true || echo false)"
HAS_HTTPX="$(bool_of dep_has 'httpx')"
HAS_PIP_AUDIT="$(bool_of dep_has 'pip-audit')"
HAS_HYPOTHESIS="$(bool_of dep_has 'hypothesis')"
if [ -f .pre-commit-config.yaml ] || [ -f .pre-commit-config.yml ] || dep_has 'pre-commit'; then HAS_PRE_COMMIT=true; else HAS_PRE_COMMIT=false; fi
HAS_TOX_NOX="$([ -f tox.ini ] || [ -f noxfile.py ] || [ "$(bool_of dep_has 'tox')" = true ] || [ "$(bool_of dep_has 'nox')" = true ] && echo true || echo false)"

# ---------- Inventory: config presence ----------------------------------------

# Ruff config: ruff.toml/.ruff.toml or [tool.ruff] in pyproject
HAS_RUFF_CONFIG="false"
RUFF_CONFIG_SOURCE=""
if [ -f "ruff.toml" ]; then HAS_RUFF_CONFIG="true"; RUFF_CONFIG_SOURCE="ruff.toml"
elif [ -f ".ruff.toml" ]; then HAS_RUFF_CONFIG="true"; RUFF_CONFIG_SOURCE=".ruff.toml"
elif [ -n "$RAW_PYPROJECT" ] && printf '%s' "$RAW_PYPROJECT" | grep -qE '^\[tool\.ruff'; then
    HAS_RUFF_CONFIG="true"; RUFF_CONFIG_SOURCE="pyproject.toml"
fi

# mypy config: mypy.ini/.mypy.ini, setup.cfg [mypy], or [tool.mypy] in pyproject
HAS_MYPY_CONFIG="false"
MYPY_CONFIG_SOURCE=""
MYPY_STRICT="false"
if [ -f "mypy.ini" ]; then HAS_MYPY_CONFIG="true"; MYPY_CONFIG_SOURCE="mypy.ini"
elif [ -f ".mypy.ini" ]; then HAS_MYPY_CONFIG="true"; MYPY_CONFIG_SOURCE=".mypy.ini"
elif [ -n "$RAW_PYPROJECT" ] && printf '%s' "$RAW_PYPROJECT" | grep -qE '^\[tool\.mypy'; then
    HAS_MYPY_CONFIG="true"; MYPY_CONFIG_SOURCE="pyproject.toml"
elif [ -f "setup.cfg" ] && grep -qE '^\[mypy\]' setup.cfg 2>/dev/null; then
    HAS_MYPY_CONFIG="true"; MYPY_CONFIG_SOURCE="setup.cfg"
fi
if [ "$HAS_MYPY_CONFIG" = "true" ]; then
    for src in mypy.ini .mypy.ini pyproject.toml setup.cfg; do
        [ -f "$src" ] || continue
        if grep -qE '^\s*strict\s*=\s*[Tt]rue' "$src" 2>/dev/null; then
            MYPY_STRICT="true"; break
        fi
    done
fi

# pytest config: pytest.ini, tox.ini [pytest], setup.cfg [tool:pytest], or pyproject [tool.pytest.ini_options]
HAS_PYTEST_CONFIG="false"
PYTEST_CONFIG_SOURCE=""
if [ -f "pytest.ini" ]; then HAS_PYTEST_CONFIG="true"; PYTEST_CONFIG_SOURCE="pytest.ini"
elif [ -n "$RAW_PYPROJECT" ] && printf '%s' "$RAW_PYPROJECT" | grep -qE '^\[tool\.pytest'; then
    HAS_PYTEST_CONFIG="true"; PYTEST_CONFIG_SOURCE="pyproject.toml"
elif [ -f "tox.ini" ] && grep -qE '^\[pytest\]' tox.ini 2>/dev/null; then
    HAS_PYTEST_CONFIG="true"; PYTEST_CONFIG_SOURCE="tox.ini"
elif [ -f "setup.cfg" ] && grep -qE '^\[tool:pytest\]' setup.cfg 2>/dev/null; then
    HAS_PYTEST_CONFIG="true"; PYTEST_CONFIG_SOURCE="setup.cfg"
fi

HAS_PYTHON_VERSION_FILE="$(bool_of test -f .python-version)"
PYTHON_VERSION_VALUE=""
[ -f ".python-version" ] && PYTHON_VERSION_VALUE="$(head -n1 .python-version 2>/dev/null | tr -d '[:space:]')"

HAS_UV_LOCK="$(bool_of test -f uv.lock)"

# py.typed marker anywhere in the tree (signals a typed, published package)
HAS_PY_TYPED="false"
if find_prune . -type f -name 'py.typed' 2>/dev/null | grep -q .; then
    HAS_PY_TYPED="true"
fi

# requirements*.txt files
REQ_FILES="$(find . -maxdepth 2 -type f -name 'requirements*.txt' 2>/dev/null | sed 's|^\./||' | sort | tr '\n' ' ' | sed -E 's/ +$//')"

# Legacy duplication signal: setup.py / setup.cfg alongside pyproject
HAS_SETUP_PY="$(bool_of test -f setup.py)"
HAS_SETUP_CFG="$(bool_of test -f setup.cfg)"
LEGACY_DUPLICATION="false"
if [ -f "pyproject.toml" ] && { [ -f "setup.py" ] || [ -f "setup.cfg" ]; }; then
    LEGACY_DUPLICATION="true"
fi

# ---------- Inventory: source layout ------------------------------------------

LAYOUT="unknown"
if [ -d "src" ]; then LAYOUT="src"; else
    # flat if there's a top-level package or top-level .py modules
    if find . -maxdepth 1 -type f -name '*.py' 2>/dev/null | grep -q . \
       || find . -maxdepth 2 -name '__init__.py' -not -path '*/.*' 2>/dev/null | grep -q .; then
        LAYOUT="flat"
    fi
fi

# Package names: directories containing __init__.py at shallow depth (under src/ or root)
PACKAGE_NAMES="$(find_prune . -type f -name '__init__.py' 2>/dev/null \
    | sed 's|^\./||' \
    | sed 's|/__init__.py$||' \
    | awk -F/ '{print $NF}' \
    | sort -u | { grep -vE '^(tests?|test)$' || true; } | tr '\n' ' ' | sed -E 's/ +$//')"

PY_FILE_COUNT="$(find_prune . -type f -name '*.py' 2>/dev/null | wc -l | tr -d ' ')"
ASYNC_DEF_COUNT="$(count_py_matches 'async[[:space:]]+def[[:space:]]')"
TYPE_IGNORE_COUNT="$(count_py_matches '#[[:space:]]*type:[[:space:]]*ignore')"
BARE_EXCEPT_COUNT="$(count_py_matches '^[[:space:]]*except[[:space:]]*:')"

# ---------- Inventory: tests --------------------------------------------------

HAS_TESTS_DIR="false"
for d in tests test; do
    [ -d "$d" ] && { HAS_TESTS_DIR="true"; break; }
done
HAS_CONFTEST="false"
if find_prune . -type f -name 'conftest.py' 2>/dev/null | grep -q .; then
    HAS_CONFTEST="true"
fi

# ---------- Inventory: git ----------------------------------------------------

HAS_GIT="false"
GIT_REMOTE_URL=""
GIT_DEFAULT_BRANCH=""
if has_cmd git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    HAS_GIT="true"
    GIT_REMOTE_URL="$(git remote get-url origin 2>/dev/null || echo "")"
    GIT_DEFAULT_BRANCH="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || echo "")"
fi

# ---------- Inventory: environment --------------------------------------------

ENV_FILES=""
for f in .env.example .env.sample .env.template .env.local.example; do
    [ -f "$f" ] && ENV_FILES="$ENV_FILES $f"
done
ENV_FILES="$(printf '%s' "$ENV_FILES" | sed -E 's/^ +//')"

# ---------- Inventory: constitution -------------------------------------------

HAS_CONSTITUTION="false"
[ -f ".specify/memory/constitution.md" ] && HAS_CONSTITUTION="true"

# ---------- Inventory: Markdown files -----------------------------------------

MD_FILES_LIST="$(find_prune . -type f \( -name '*.md' -o -name '*.mdx' \) 2>/dev/null | sed 's|^\./||' | sort)"
MD_FILES_TOTAL=0
[ -n "$MD_FILES_LIST" ] && MD_FILES_TOTAL="$(printf '%s\n' "$MD_FILES_LIST" | wc -l | tr -d ' ')"

KNOWN_DOCS=""
for f in README.md README.MD ARCHITECTURE.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md \
         CHANGELOG.md AGENTS.md CLAUDE.md GEMINI.md .github/copilot-instructions.md; do
    [ -f "$f" ] && KNOWN_DOCS="$KNOWN_DOCS $f"
done
KNOWN_DOCS="$(printf '%s' "$KNOWN_DOCS" | sed -E 's/^ +//')"

# ---------- Emit output -------------------------------------------------------

if [ "$JSON_MODE" = true ]; then
    if has_cmd python3; then
        SPECKIT_REPO_ROOT="$REPO_ROOT" \
        SPECKIT_PYPROJECT_INV="$PYPROJECT_INVENTORY" \
        SPECKIT_PYPROJECT_PRESENT="$([ -n "$PYPROJECT_PATH" ] && echo true || echo false)" \
        SPECKIT_HAS_UV="$HAS_UV" \
        SPECKIT_HAS_POETRY="$HAS_POETRY" \
        SPECKIT_HAS_RUFF="$HAS_RUFF" \
        SPECKIT_HAS_BLACK="$HAS_BLACK" \
        SPECKIT_HAS_MYPY="$HAS_MYPY" \
        SPECKIT_HAS_PYRIGHT="$HAS_PYRIGHT" \
        SPECKIT_HAS_PYTEST="$HAS_PYTEST" \
        SPECKIT_HAS_PYDANTIC="$HAS_PYDANTIC" \
        SPECKIT_HAS_ATTRS="$HAS_ATTRS" \
        SPECKIT_HAS_SQLALCHEMY="$HAS_SQLALCHEMY" \
        SPECKIT_HAS_FASTAPI="$HAS_FASTAPI" \
        SPECKIT_HAS_FLASK="$HAS_FLASK" \
        SPECKIT_HAS_DJANGO="$HAS_DJANGO" \
        SPECKIT_HAS_LITESTAR="$HAS_LITESTAR" \
        SPECKIT_HAS_TYPER="$HAS_TYPER" \
        SPECKIT_HAS_CLICK="$HAS_CLICK" \
        SPECKIT_HAS_CELERY="$HAS_CELERY" \
        SPECKIT_HAS_HTTPX="$HAS_HTTPX" \
        SPECKIT_HAS_PIP_AUDIT="$HAS_PIP_AUDIT" \
        SPECKIT_HAS_HYPOTHESIS="$HAS_HYPOTHESIS" \
        SPECKIT_HAS_PRE_COMMIT="$HAS_PRE_COMMIT" \
        SPECKIT_HAS_TOX_NOX="$HAS_TOX_NOX" \
        SPECKIT_HAS_RUFF_CONFIG="$HAS_RUFF_CONFIG" \
        SPECKIT_RUFF_CONFIG_SRC="$RUFF_CONFIG_SOURCE" \
        SPECKIT_HAS_MYPY_CONFIG="$HAS_MYPY_CONFIG" \
        SPECKIT_MYPY_CONFIG_SRC="$MYPY_CONFIG_SOURCE" \
        SPECKIT_MYPY_STRICT="$MYPY_STRICT" \
        SPECKIT_HAS_PYTEST_CONFIG="$HAS_PYTEST_CONFIG" \
        SPECKIT_PYTEST_CONFIG_SRC="$PYTEST_CONFIG_SOURCE" \
        SPECKIT_HAS_PYTHON_VERSION="$HAS_PYTHON_VERSION_FILE" \
        SPECKIT_PYTHON_VERSION_VALUE="$PYTHON_VERSION_VALUE" \
        SPECKIT_HAS_UV_LOCK="$HAS_UV_LOCK" \
        SPECKIT_HAS_PY_TYPED="$HAS_PY_TYPED" \
        SPECKIT_REQ_FILES="$REQ_FILES" \
        SPECKIT_HAS_SETUP_PY="$HAS_SETUP_PY" \
        SPECKIT_HAS_SETUP_CFG="$HAS_SETUP_CFG" \
        SPECKIT_LEGACY_DUP="$LEGACY_DUPLICATION" \
        SPECKIT_LAYOUT="$LAYOUT" \
        SPECKIT_PACKAGE_NAMES="$PACKAGE_NAMES" \
        SPECKIT_PY_FILE_COUNT="$PY_FILE_COUNT" \
        SPECKIT_ASYNC_DEF_COUNT="$ASYNC_DEF_COUNT" \
        SPECKIT_TYPE_IGNORE_COUNT="$TYPE_IGNORE_COUNT" \
        SPECKIT_BARE_EXCEPT_COUNT="$BARE_EXCEPT_COUNT" \
        SPECKIT_HAS_TESTS_DIR="$HAS_TESTS_DIR" \
        SPECKIT_HAS_CONFTEST="$HAS_CONFTEST" \
        SPECKIT_HAS_GIT="$HAS_GIT" \
        SPECKIT_GIT_REMOTE="$GIT_REMOTE_URL" \
        SPECKIT_GIT_DEFAULT_BRANCH="$GIT_DEFAULT_BRANCH" \
        SPECKIT_ENV_FILES="$ENV_FILES" \
        SPECKIT_HAS_CONSTITUTION="$HAS_CONSTITUTION" \
        SPECKIT_MD_FILES="$MD_FILES_LIST" \
        SPECKIT_MD_TOTAL="$MD_FILES_TOTAL" \
        SPECKIT_KNOWN_DOCS="$KNOWN_DOCS" \
        SPECKIT_MD_HEAD_BYTES="$SCAN_MD_HEAD_BYTES" \
        SPECKIT_MD_MAX="$MAX_MD_FILES" \
        python3 <<'PY'
import json, os, re

def env(name, default=""):
    return os.environ.get(name, default)

def as_bool(s): return s == "true"
def as_int(s):
    try: return int(s)
    except Exception: return 0
def split_ws(s):
    return [x for x in (s or "").split() if x]
def parse_json_or(s, fallback=None):
    if not s: return fallback if fallback is not None else {}
    try: return json.loads(s)
    except Exception: return {"error": "embedded JSON invalid", "raw_len": len(s)}

repo_root = env("SPECKIT_REPO_ROOT")
md_head_bytes = max(0, as_int(env("SPECKIT_MD_HEAD_BYTES", "4096")))
md_max = max(1, as_int(env("SPECKIT_MD_MAX", "200")))

md_files = [p for p in (env("SPECKIT_MD_FILES") or "").splitlines() if p.strip()]
md_total = as_int(env("SPECKIT_MD_TOTAL"))

def file_summary(rel_path):
    full = os.path.join(repo_root, rel_path)
    info = {"path": rel_path}
    try:
        st = os.stat(full)
        info["size"] = st.st_size
    except Exception:
        info["error"] = "stat failed"
        return info
    try:
        with open(full, "rb") as f:
            head = f.read(md_head_bytes)
        text = head.decode("utf-8", errors="replace")
        headings = []
        for line in text.splitlines():
            m = re.match(r"^(#{1,6})\s+(.*\S)\s*$", line)
            if m:
                headings.append({"level": len(m.group(1)), "text": m.group(2)[:200]})
            if len(headings) >= 25:
                break
        info["headings"] = headings
        excerpt = ""
        for line in text.splitlines():
            s = line.strip()
            if not s or s.startswith("#") or s.startswith("<!--"):
                continue
            excerpt = s[:300]; break
        info["excerpt"] = excerpt
    except Exception as e:
        info["error"] = f"read failed: {e}"
    return info

md_summaries = [file_summary(p) for p in md_files[:md_max]]
md_truncated = md_total > md_max

pyproject = parse_json_or(env("SPECKIT_PYPROJECT_INV"), fallback={"present": False})

result = {
    "schema_version": "1.0",
    "repo_root": repo_root,
    "pyproject": pyproject,
    "tooling": {
        "has_uv":         as_bool(env("SPECKIT_HAS_UV")),
        "has_poetry":     as_bool(env("SPECKIT_HAS_POETRY")),
        "has_ruff":       as_bool(env("SPECKIT_HAS_RUFF")),
        "has_black":      as_bool(env("SPECKIT_HAS_BLACK")),
        "has_mypy":       as_bool(env("SPECKIT_HAS_MYPY")),
        "has_pyright":    as_bool(env("SPECKIT_HAS_PYRIGHT")),
        "has_pytest":     as_bool(env("SPECKIT_HAS_PYTEST")),
        "has_pydantic":   as_bool(env("SPECKIT_HAS_PYDANTIC")),
        "has_attrs":      as_bool(env("SPECKIT_HAS_ATTRS")),
        "has_sqlalchemy": as_bool(env("SPECKIT_HAS_SQLALCHEMY")),
        "has_fastapi":    as_bool(env("SPECKIT_HAS_FASTAPI")),
        "has_flask":      as_bool(env("SPECKIT_HAS_FLASK")),
        "has_django":     as_bool(env("SPECKIT_HAS_DJANGO")),
        "has_litestar":   as_bool(env("SPECKIT_HAS_LITESTAR")),
        "has_typer":      as_bool(env("SPECKIT_HAS_TYPER")),
        "has_click":      as_bool(env("SPECKIT_HAS_CLICK")),
        "has_task_queue": as_bool(env("SPECKIT_HAS_CELERY")),
        "has_httpx":      as_bool(env("SPECKIT_HAS_HTTPX")),
        "has_pip_audit":  as_bool(env("SPECKIT_HAS_PIP_AUDIT")),
        "has_hypothesis": as_bool(env("SPECKIT_HAS_HYPOTHESIS")),
        "has_pre_commit": as_bool(env("SPECKIT_HAS_PRE_COMMIT")),
        "has_tox_nox":    as_bool(env("SPECKIT_HAS_TOX_NOX")),
    },
    "config": {
        "ruff": {
            "present": as_bool(env("SPECKIT_HAS_RUFF_CONFIG")),
            "source":  env("SPECKIT_RUFF_CONFIG_SRC") or None,
        },
        "mypy": {
            "present": as_bool(env("SPECKIT_HAS_MYPY_CONFIG")),
            "source":  env("SPECKIT_MYPY_CONFIG_SRC") or None,
            "strict":  as_bool(env("SPECKIT_MYPY_STRICT")),
        },
        "pytest": {
            "present": as_bool(env("SPECKIT_HAS_PYTEST_CONFIG")),
            "source":  env("SPECKIT_PYTEST_CONFIG_SRC") or None,
        },
        "python_version_file": {
            "present": as_bool(env("SPECKIT_HAS_PYTHON_VERSION")),
            "value":   env("SPECKIT_PYTHON_VERSION_VALUE") or None,
        },
        "py_typed_marker": as_bool(env("SPECKIT_HAS_PY_TYPED")),
        "uv_lock":         as_bool(env("SPECKIT_HAS_UV_LOCK")),
        "requirements_files": split_ws(env("SPECKIT_REQ_FILES")),
        "setup_py":        as_bool(env("SPECKIT_HAS_SETUP_PY")),
        "setup_cfg":       as_bool(env("SPECKIT_HAS_SETUP_CFG")),
        "legacy_duplication": as_bool(env("SPECKIT_LEGACY_DUP")),
    },
    "source_layout": {
        "layout":         env("SPECKIT_LAYOUT") or "unknown",
        "package_names":  split_ws(env("SPECKIT_PACKAGE_NAMES")),
        "py_file_count":  as_int(env("SPECKIT_PY_FILE_COUNT")),
        "async_def_count":   as_int(env("SPECKIT_ASYNC_DEF_COUNT")),
        "type_ignore_count": as_int(env("SPECKIT_TYPE_IGNORE_COUNT")),
        "bare_except_count": as_int(env("SPECKIT_BARE_EXCEPT_COUNT")),
    },
    "testing": {
        "has_tests_directory": as_bool(env("SPECKIT_HAS_TESTS_DIR")),
        "has_conftest":        as_bool(env("SPECKIT_HAS_CONFTEST")),
    },
    "git": {
        "is_repo":        as_bool(env("SPECKIT_HAS_GIT")),
        "origin_url":     env("SPECKIT_GIT_REMOTE") or None,
        "default_branch": env("SPECKIT_GIT_DEFAULT_BRANCH") or None,
    },
    "environment": {
        "env_example_files": split_ws(env("SPECKIT_ENV_FILES")),
        "requires_python":   pyproject.get("requires_python") if isinstance(pyproject, dict) else None,
    },
    "constitution": {
        "exists": as_bool(env("SPECKIT_HAS_CONSTITUTION")),
        "path":   ".specify/memory/constitution.md",
    },
    "markdown": {
        "total":      md_total,
        "listed":     len(md_summaries),
        "truncated":  md_truncated,
        "known_docs": split_ws(env("SPECKIT_KNOWN_DOCS")),
        "files":      md_summaries,
    },
}
print(json.dumps(result, indent=2))
PY
    else
        # Minimal JSON fallback (no python3)
        printf '{\n'
        printf '  "schema_version": "1.0",\n'
        printf '  "warning": "python3 unavailable; emitting limited fallback inventory",\n'
        printf '  "repo_root": "%s",\n' "$(json_escape "$REPO_ROOT")"
        printf '  "pyproject_present": %s,\n' "$([ -n "$PYPROJECT_PATH" ] && echo true || echo false)"
        printf '  "has_uv": %s,\n' "$HAS_UV"
        printf '  "has_ruff": %s,\n' "$HAS_RUFF"
        printf '  "has_mypy": %s,\n' "$HAS_MYPY"
        printf '  "has_pytest": %s,\n' "$HAS_PYTEST"
        printf '  "py_file_count": %s,\n' "$PY_FILE_COUNT"
        printf '  "markdown_total": %s\n' "$MD_FILES_TOTAL"
        printf '}\n'
    fi
else
    # Human-readable summary
    echo "Repo root:           $REPO_ROOT"
    echo "pyproject.toml:      $([ -n "$PYPROJECT_PATH" ] && echo present || echo absent)"
    echo "Source layout:       $LAYOUT"
    echo "Package names:       $PACKAGE_NAMES"
    echo ".py file count:      $PY_FILE_COUNT"
    echo "async def count:     $ASYNC_DEF_COUNT"
    echo "# type: ignore:      $TYPE_IGNORE_COUNT"
    echo "bare except count:   $BARE_EXCEPT_COUNT"
    echo "uv (uv.lock):        $HAS_UV"
    echo "Poetry:              $HAS_POETRY"
    echo "Ruff:                $HAS_RUFF (config: ${RUFF_CONFIG_SOURCE:-none})"
    echo "mypy:                $HAS_MYPY (strict: $MYPY_STRICT)"
    echo "pytest:              $HAS_PYTEST (config: ${PYTEST_CONFIG_SOURCE:-none})"
    echo "Pydantic:            $HAS_PYDANTIC"
    echo "FastAPI/Flask/Django:$HAS_FASTAPI / $HAS_FLASK / $HAS_DJANGO"
    echo "py.typed marker:     $HAS_PY_TYPED"
    echo "Legacy setup dup:    $LEGACY_DUPLICATION"
    echo "Tests directory:     $HAS_TESTS_DIR (conftest: $HAS_CONFTEST)"
    echo ".python-version:     ${PYTHON_VERSION_VALUE:-absent}"
    echo "Env example files:   $ENV_FILES"
    echo "Git repository:      $HAS_GIT"
    echo "Constitution file:   $HAS_CONSTITUTION"
    echo "Markdown files:      $MD_FILES_TOTAL"
    if [ -n "$KNOWN_DOCS" ]; then
        echo "Known docs:"
        for f in $KNOWN_DOCS; do echo "  - $f"; done
    fi
fi
