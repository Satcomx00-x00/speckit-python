#!/usr/bin/env bash
# audit-codebase.sh — audit a Python codebase against the behavioral directives
# in the project constitution. Emits a structured JSON report of findings with
# file:line locations, rule metadata, and remediation hints.
#
# Companion command: /speckit.audit (and /speckit.audit.deep, which runs this
# script *plus* extra techniques: mypy --strict, ruff check, pip-audit, and
# LLM cross-file analysis).
#
# Designed for big codebases:
#   - Source files enumerated once into a cached list.
#   - Rule scanners use `xargs -P` for parallel grep.
#   - `--max-findings-per-rule` and `--paths` keep output bounded.

set -eu
# Intentionally NOT setting `pipefail`: many scan pipelines run grep through
# xargs and grep returns 1 when a file has no match. With pipefail, xargs
# reports those as 123 and the pipeline aborts. Each scan tolerates failure
# locally where it matters; missing findings are not a script error.

# ---------- Defaults ----------------------------------------------------------

JSON_MODE=true
REPO_ROOT_ARG=""
MAX_PER_RULE="${SPECKIT_AUDIT_MAX_PER_RULE:-50}"
PARALLEL="${SPECKIT_AUDIT_PARALLEL:-4}"
PATHS_ARG=""
RULES_ARG=""           # comma-separated rule IDs (subset)
SECTIONS_ARG=""        # comma-separated section prefixes (subset)
MIN_SEVERITY="low"     # critical|high|medium|low
SNIPPET_MAX_LEN=200
OUTPUT_FILE=""
LIST_RULES_ONLY=false

print_help() {
    cat <<EOF
Usage: $0 [options]

Audits a Python repository against the constitution's behavioral directives.

Options:
  --root <path>                    Repository root (default: auto-detect)
  --paths <p1,p2,...>              Limit scan to these paths (relative to root)
  --rules <id1,id2,...>            Run only these rule IDs
  --sections <S1,S2,...>           Run only these section prefixes
                                   (TYPE,QUAL,ARCH,DATA,ERR,SEC,PERF,TEST,PKG)
  --severity <critical|high|medium|low>
                                   Minimum severity to include (default: low)
  --max-findings-per-rule <N>      Cap findings per rule (default: 50)
  --parallel <N>                   xargs parallelism (default: 4)
  --output <file>                  Write report to file instead of stdout
  --text                           Emit human-readable summary instead of JSON
  --json                           Emit JSON (default)
  --list-rules                     Print rule catalog as JSON and exit
  --help, -h                       Show this help and exit

Environment:
  SPECKIT_AUDIT_MAX_PER_RULE       Default max findings per rule
  SPECKIT_AUDIT_PARALLEL           Default xargs parallelism

Rule sections:
  TYPE  — Type Safety & Static Analysis
  QUAL  — Code Quality & Style
  ARCH  — Architecture & Design
  DATA  — Data, Validation & Boundaries
  ERR   — Error Handling & Resilience
  SEC   — Security
  PERF  — Performance
  TEST  — Testing
  PKG   — Packaging, Tooling & Dependencies

Exit codes:
  0   No critical findings (subject to filters)
  1   At least one critical finding
  2   Usage error
EOF
}

# ---------- Arg parsing -------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --root)                    REPO_ROOT_ARG="$2"; shift 2 ;;
        --paths)                   PATHS_ARG="$2"; shift 2 ;;
        --rules)                   RULES_ARG="$2"; shift 2 ;;
        --sections)                SECTIONS_ARG="$2"; shift 2 ;;
        --severity)                MIN_SEVERITY="$2"; shift 2 ;;
        --max-findings-per-rule)   MAX_PER_RULE="$2"; shift 2 ;;
        --parallel)                PARALLEL="$2"; shift 2 ;;
        --output)                  OUTPUT_FILE="$2"; shift 2 ;;
        --text)                    JSON_MODE=false; shift ;;
        --json)                    JSON_MODE=true; shift ;;
        --list-rules)              LIST_RULES_ONLY=true; shift ;;
        -h|--help)                 print_help; exit 0 ;;
        *)                         echo "Unknown argument: $1" >&2; print_help >&2; exit 2 ;;
    esac
done

case "$MIN_SEVERITY" in critical|high|medium|low) ;; *)
    echo "Error: --severity must be one of critical, high, medium, low" >&2; exit 2 ;;
esac

# ---------- Resolve repo root -------------------------------------------------

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "$REPO_ROOT_ARG" ]; then
    REPO_ROOT="$(CDPATH="" cd "$REPO_ROOT_ARG" 2>/dev/null && pwd)" || {
        echo "Error: --root path does not exist: $REPO_ROOT_ARG" >&2; exit 1
    }
elif [ -f "$SCRIPT_DIR/../../../../scripts/bash/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/../../../../scripts/bash/common.sh"
    REPO_ROOT="$(get_repo_root)"
elif command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT="$(git rev-parse --show-toplevel)"
else
    REPO_ROOT="$(pwd)"
fi
cd "$REPO_ROOT"

# ---------- Helpers -----------------------------------------------------------

has_cmd() { command -v "$1" >/dev/null 2>&1; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

FILES_LIST="$WORKDIR/files.txt"
FINDINGS_DIR="$WORKDIR/findings"
mkdir -p "$FINDINGS_DIR"

# Numeric severity for filtering
sev_rank() {
    case "$1" in critical) echo 4 ;; high) echo 3 ;; medium) echo 2 ;; low) echo 1 ;; *) echo 0 ;; esac
}
MIN_RANK="$(sev_rank "$MIN_SEVERITY")"

# Whether a rule should run, given --rules / --sections filters
rule_enabled() {
    local rule_id="$1" section
    section="${rule_id%%.*}"
    if [ -n "$RULES_ARG" ] && ! grep -qE "(^|,)$rule_id(,|$)" <<< "$RULES_ARG"; then
        return 1
    fi
    if [ -n "$SECTIONS_ARG" ] && ! grep -qiE "(^|,)$section(,|$)" <<< "$SECTIONS_ARG"; then
        return 1
    fi
    return 0
}

# Severity passes the filter
severity_passes() {
    local sev="$1"
    [ "$(sev_rank "$sev")" -ge "$MIN_RANK" ]
}

# Trim snippet to a single line, max length
trim_snippet() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    if [ "${#s}" -gt "$SNIPPET_MAX_LEN" ]; then
        s="${s:0:$SNIPPET_MAX_LEN}..."
    fi
    printf '%s' "$s"
}

# Emit a finding as NDJSON to the rule's output file
# Args: rule_id severity file line snippet
emit_finding() {
    local rule_id="$1" sev="$2" file="$3" line="$4" snippet="$5"
    severity_passes "$sev" || return 0

    local out="$FINDINGS_DIR/$rule_id.ndjson"
    if [ -f "$out" ] && [ "$(wc -l < "$out" | tr -d ' ')" -ge "$MAX_PER_RULE" ]; then
        return 0
    fi

    if has_cmd python3; then
        SPECKIT_RID="$rule_id" SPECKIT_SEV="$sev" SPECKIT_FILE="$file" \
        SPECKIT_LINE="$line" SPECKIT_SNIP="$snippet" \
        python3 -c "
import json, os
ln = os.environ['SPECKIT_LINE']
print(json.dumps({
    'rule_id':  os.environ['SPECKIT_RID'],
    'severity': os.environ['SPECKIT_SEV'],
    'file':     os.environ['SPECKIT_FILE'],
    'line':     int(ln) if ln.isdigit() else None,
    'snippet':  os.environ['SPECKIT_SNIP'],
}))" >> "$out"
    else
        local esc_file esc_snip
        esc_file="$(printf '%s' "$file"    | sed 's/\\/\\\\/g; s/"/\\"/g')"
        esc_snip="$(printf '%s' "$snippet" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')"
        printf '{"rule_id":"%s","severity":"%s","file":"%s","line":%s,"snippet":"%s"}\n' \
            "$rule_id" "$sev" "$esc_file" "${line:-null}" "$esc_snip" >> "$out"
    fi
}

# ---------- Rule catalog ------------------------------------------------------
#
# Each rule: ID|severity|section|phase|directive|remediation
# Sections/phases match the constitution. The catalog drives both evaluation
# and reporting; --list-rules prints it as JSON.

declare -a RULE_IDS RULE_META
register_rule() {
    RULE_IDS+=("$1")
    RULE_META+=("$2|$3|$4|$5|$6")  # sev|section|phase|directive|remediation
}

# -- Security ----------------------------------------------------------------
register_rule "SEC.EVAL.eval-exec"          "critical" "Security"                       "P2" "No eval/exec/compile on untrusted input"                        "Remove eval()/exec(); parse input into typed structures or dispatch via an explicit mapping."
register_rule "SEC.SHELL.shell-true"        "critical" "Security"                       "P2" "No subprocess(..., shell=True) with interpolated values"        "Pass an argument list (shell=False) and avoid the shell; never interpolate user data into a command string."
register_rule "SEC.DESER.pickle-loads"      "critical" "Security"                       "P2" "No insecure deserialization of untrusted bytes"                 "Replace pickle with a safe format (JSON, msgpack with schema); never unpickle external data."
register_rule "SEC.DESER.yaml-load"         "critical" "Security"                       "P2" "Never yaml.load untrusted bytes"                                "Use yaml.safe_load() (or an explicit SafeLoader) for any external YAML."
register_rule "SEC.SQL.string-sql"          "high"     "Security"                       "P2" "Parameterized queries everywhere; ban string-built SQL"          "Use bound parameters / placeholders; never f-string or concatenate user data into SQL."
register_rule "SEC.RANDOM.insecure-token"   "medium"   "Security"                       "P2" "Use secrets, not random, for tokens and secrets"                 "Replace random.* with the secrets module (secrets.token_urlsafe, secrets.choice) for security-sensitive values."
register_rule "SEC.TLS.verify-false"        "high"     "Security"                       "P2" "Verify TLS on every outbound request"                            "Remove verify=False; trust the system CA bundle or pass a proper CA path."

# -- Type Safety & Static Analysis -------------------------------------------
register_rule "TYPE.ANY.any-annotation"     "high"     "Type Safety & Static Analysis"  "P1" "Ban Any in signatures; use precise types or narrowing"           "Replace Any with a precise type, object + narrowing, or a Protocol."
register_rule "TYPE.IGNORE.bare-type-ignore" "high"    "Type Safety & Static Analysis"  "P1" "Ban bare # type: ignore; require a code and reason"              "Use '# type: ignore[code]  # reason' with the specific error code and a justification."
register_rule "TYPE.CAST.cast-usage"        "low"      "Type Safety & Static Analysis"  "P2" "Reserve cast() for genuinely un-expressible narrowing"           "Prefer a type guard, assert, or schema parse; use cast() only when narrowing cannot be expressed otherwise."

# -- Error Handling & Resilience ---------------------------------------------
register_rule "ERR.EXCEPT.bare-except"      "critical" "Error Handling & Resilience"    "P1" "Ban bare except:; catch the narrowest exception"                 "Catch a specific exception type and handle it deliberately; never use a bare 'except:'."
register_rule "ERR.EXCEPT.except-pass"      "high"     "Error Handling & Resilience"    "P1" "Ban silent except ...: pass"                                     "Handle or log the error; if truly ignorable, comment why and narrow the exception type."
register_rule "ERR.EXCEPT.broad-except"     "medium"   "Error Handling & Resilience"    "P2" "Avoid broad 'except Exception'; catch where you can act"          "Catch the narrowest exception you can handle; let unexpected errors surface to a single top-level boundary."

# -- Code Quality & Style ----------------------------------------------------
register_rule "QUAL.PRINT.print-debug"      "medium"   "Code Quality & Style"           "P3" "Use the logger, not print, for diagnostics"                      "Replace print() with a logging call; reserve print for CLI/__main__ output."
register_rule "QUAL.IMPORT.wildcard-import" "medium"   "Code Quality & Style"           "P3" "Ban wildcard imports"                                            "Import the specific names you use; 'from x import *' hides origins and breaks tooling."
register_rule "QUAL.OSPATH.os-path"         "low"      "Code Quality & Style"           "P3" "Prefer pathlib.Path over os.path"                                "Use pathlib.Path for filesystem paths; it is safer and more expressive than os.path."

# -- Data, Validation & Boundaries -------------------------------------------
register_rule "DATA.ENV.adhoc-environ"      "medium"   "Data, Validation & Boundaries"  "P2" "Never read os.environ[...] ad-hoc deep in the code"              "Validate environment at startup with a typed settings model; read config through it, not os.environ directly."

# -- Architecture & Design ---------------------------------------------------
register_rule "ARCH.IO.now-in-logic"        "low"      "Architecture & Design"          "P1" "Inject the clock; don't reach for datetime.now() in logic"        "Pass a clock/now-provider into the function; keep business logic deterministic and testable."

# -- Performance -------------------------------------------------------------
register_rule "PERF.CONCAT.str-concat-loop" "low"      "Performance"                    "P2" "No string concatenation in loops"                                "Accumulate into a list and ''.join(...) once, or use io.StringIO; '+=' in a loop is O(n^2)."

# -- Packaging, Tooling & Dependencies ---------------------------------------
register_rule "PKG.SETUP.legacy-setup"      "low"      "Packaging, Tooling & Dependencies" "P1" "Single source of metadata: pyproject.toml; no setup.py duplication" "Migrate setup.py/setup.cfg metadata into pyproject.toml (PEP 621) and remove the legacy files."

# -- Testing -----------------------------------------------------------------
register_rule "TEST.ASSERTTRUE.assert-true" "low"      "Testing"                        "P2" "Avoid assertion-free / tautological tests (assert True)"          "Assert on real behavior and outputs; 'assert True' provides no coverage signal."

# ---------- --list-rules short-circuit ----------------------------------------

if [ "$LIST_RULES_ONLY" = true ]; then
    if has_cmd python3; then
        printf '%s\n' "${RULE_IDS[@]}" > "$WORKDIR/ids.txt"
        printf '%s\n' "${RULE_META[@]}" > "$WORKDIR/meta.txt"
        SPECKIT_W="$WORKDIR" python3 <<'PY'
import json, os
w = os.environ["SPECKIT_W"]
ids  = [l.rstrip("\n") for l in open(os.path.join(w, "ids.txt"),  encoding="utf-8") if l.strip()]
meta = [l.rstrip("\n") for l in open(os.path.join(w, "meta.txt"), encoding="utf-8") if l.strip()]
rules = []
for rid, m in zip(ids, meta):
    sev, section, phase, directive, remediation = m.split("|", 4)
    rules.append({
        "id": rid, "severity": sev, "section": section, "phase": phase,
        "directive": directive, "remediation": remediation,
    })
print(json.dumps({"schema_version": "1.0", "rules": rules}, indent=2))
PY
    else
        echo '{"error":"python3 unavailable; cannot render rule catalog"}'
    fi
    exit 0
fi

# ---------- File enumeration --------------------------------------------------

IGNORE_DIRS=(.git .venv venv node_modules __pycache__ .mypy_cache .ruff_cache .pytest_cache dist build .tox .nox .eggs .specify .cache)

enumerate_into() {
    local out="$1"; shift
    local roots=("$@")
    [ "${#roots[@]}" -eq 0 ] && roots=(".")

    local prune=()
    local first=true
    for d in "${IGNORE_DIRS[@]}"; do
        if $first; then
            prune+=("(" "-type" "d" "-name" "$d"); first=false
        else
            prune+=("-o" "-type" "d" "-name" "$d")
        fi
    done
    prune+=(")")

    : > "$out"
    local root
    for root in "${roots[@]}"; do
        if [ ! -e "$root" ]; then
            echo "[audit] Warning: path '$root' does not exist; skipping" >&2
            continue
        fi
        find "$root" "${prune[@]}" -prune -o \
            -type f \( -name '*.py' -o -name '*.pyi' \) -print 2>/dev/null \
            | sed 's|^\./||' >> "$out"
    done
    sort -u -o "$out" "$out"
}

if [ -n "$PATHS_ARG" ]; then
    IFS=',' read -r -a SCAN_PATHS <<< "$PATHS_ARG"
    enumerate_into "$FILES_LIST" "${SCAN_PATHS[@]}"
else
    enumerate_into "$FILES_LIST" "."
fi

FILES_SCANNED="$(wc -l < "$FILES_LIST" | tr -d ' ')"

# Filter the file list to exclude test files (for rules that should skip tests)
prod_files() {
    grep -vE '(^|/)(tests?|test)/|(^|/)test_[^/]*\.py$|_test\.py$|conftest\.py$' "$FILES_LIST" || true
}

# ---------- Generic regex-scanner over the file list -------------------------
# scan_regex <rule_id> <severity> <regex> [--exclude-tests] [--prefer-pcre]
scan_regex() {
    local rule="$1" sev="$2" pattern="$3"
    shift 3
    rule_enabled "$rule" || return 0
    [ "$FILES_SCANNED" -eq 0 ] && return 0

    local exclude_tests=false prefer_pcre=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --exclude-tests) exclude_tests=true; shift ;;
            --prefer-pcre)   prefer_pcre=true; shift ;;
            *) shift ;;
        esac
    done

    local list="$FILES_LIST"
    if $exclude_tests; then
        list="$WORKDIR/.list.$rule"
        prod_files > "$list"
    fi
    [ ! -s "$list" ] && return 0

    local grep_flags="-HnE"
    if $prefer_pcre && printf 'x' | grep -qP 'x' 2>/dev/null; then
        grep_flags="-HnP"
    fi

    # Parallel grep, capped output. tr/xargs feed the file list as NUL-delimited.
    < "$list" tr '\n' '\0' | xargs -0 -P "$PARALLEL" -n 50 grep "$grep_flags" "$pattern" 2>/dev/null \
        | head -n $((MAX_PER_RULE * 4)) \
        | while IFS= read -r match; do
            local file rest line content snippet
            file="${match%%:*}"
            rest="${match#*:}"
            line="${rest%%:*}"
            content="${rest#*:}"
            snippet="$(trim_snippet "$content")"
            emit_finding "$rule" "$sev" "$file" "$line" "$snippet"
        done
}

# ---------- Multiline regex scanner (python-backed) --------------------------
# scan_multiline <rule_id> <severity> <python-regex> [--exclude-tests]
# Used for patterns that span lines (e.g. except: \n pass). Reports the line
# of the match start.
scan_multiline() {
    local rule="$1" sev="$2" pattern="$3"
    shift 3
    rule_enabled "$rule" || return 0
    has_cmd python3 || return 0
    [ "$FILES_SCANNED" -eq 0 ] && return 0

    local exclude_tests=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --exclude-tests) exclude_tests=true; shift ;;
            *) shift ;;
        esac
    done

    local list="$FILES_LIST"
    if $exclude_tests; then
        list="$WORKDIR/.mlist.$rule"
        prod_files > "$list"
    fi
    [ ! -s "$list" ] && return 0

    SPECKIT_RID="$rule" SPECKIT_SEV="$sev" SPECKIT_PAT="$pattern" \
    SPECKIT_LIST="$list" SPECKIT_MAX="$MAX_PER_RULE" SPECKIT_SNIPMAX="$SNIPPET_MAX_LEN" \
    python3 <<'PY' >> "$FINDINGS_DIR/$rule.ndjson"
import json, os, re

rid = os.environ["SPECKIT_RID"]
sev = os.environ["SPECKIT_SEV"]
pat = re.compile(os.environ["SPECKIT_PAT"])
max_per = int(os.environ["SPECKIT_MAX"])
snipmax = int(os.environ["SPECKIT_SNIPMAX"])

emitted = 0
with open(os.environ["SPECKIT_LIST"], encoding="utf-8") as lf:
    files = [l.strip() for l in lf if l.strip()]

for f in files:
    if emitted >= max_per:
        break
    try:
        with open(f, "rb") as fh:
            raw = fh.read()
        if b"\x00" in raw:
            continue
        text = raw.decode("utf-8", errors="replace")
    except Exception:
        continue
    for m in pat.finditer(text):
        if emitted >= max_per:
            break
        line_no = text.count("\n", 0, m.start()) + 1
        snippet = " ".join(m.group(0).split())[:snipmax]
        print(json.dumps({
            "rule_id": rid, "severity": sev, "file": f,
            "line": line_no, "snippet": snippet,
        }))
        emitted += 1
PY
}

# ---------- File-level scanner (one finding per matching file) ----------------
# scan_file_present <rule_id> <severity> <file-path> <snippet>
scan_file_present() {
    local rule="$1" sev="$2" path="$3" snippet="$4"
    rule_enabled "$rule" || return 0
    [ -f "$path" ] && emit_finding "$rule" "$sev" "$path" 1 "$snippet"
}

# ---------- Rule scanners -----------------------------------------------------

# SEC.EVAL.eval-exec
scan_eval_exec() {
    scan_regex "SEC.EVAL.eval-exec" "critical" '\beval\(|\bexec\('
}

# SEC.SHELL.shell-true
scan_shell_true() {
    scan_regex "SEC.SHELL.shell-true" "critical" 'shell[[:space:]]*=[[:space:]]*True'
}

# SEC.DESER.pickle-loads
scan_pickle_loads() {
    scan_regex "SEC.DESER.pickle-loads" "critical" 'pickle\.loads?\('
}

# SEC.DESER.yaml-load — yaml.load( without a SafeLoader on the same line
scan_yaml_load() {
    rule_enabled "SEC.DESER.yaml-load" || return 0
    if printf 'x' | grep -qP 'x' 2>/dev/null; then
        scan_regex "SEC.DESER.yaml-load" "critical" 'yaml\.load\((?!.*SafeLoader)' --prefer-pcre
    else
        # POSIX fallback: match yaml.load( then drop lines that mention SafeLoader.
        [ "$FILES_SCANNED" -eq 0 ] && return 0
        < "$FILES_LIST" tr '\n' '\0' | xargs -0 -P "$PARALLEL" -n 50 \
            grep -HnE 'yaml\.load\(' 2>/dev/null \
            | grep -vE 'SafeLoader' \
            | head -n $((MAX_PER_RULE * 4)) \
            | while IFS= read -r match; do
                local file rest line content snippet
                file="${match%%:*}"; rest="${match#*:}"
                line="${rest%%:*}"; content="${rest#*:}"
                snippet="$(trim_snippet "$content")"
                emit_finding "SEC.DESER.yaml-load" "critical" "$file" "$line" "$snippet"
            done
    fi
}

# SEC.SQL.string-sql — execute(...) with SQL keyword and % or + interpolation
scan_string_sql() {
    scan_regex "SEC.SQL.string-sql" "high" \
        '(execute|executemany)\([[:space:]]*f?["'\''].*(SELECT|INSERT|UPDATE|DELETE).*(%|\+)'
}

# SEC.RANDOM.insecure-token — random.* on a line mentioning token/secret/password
scan_insecure_token() {
    rule_enabled "SEC.RANDOM.insecure-token" || return 0
    [ "$FILES_SCANNED" -eq 0 ] && return 0
    < "$FILES_LIST" tr '\n' '\0' | xargs -0 -P "$PARALLEL" -n 50 \
        grep -HniE 'random\.(random|choice|randint|randrange|getrandbits)' 2>/dev/null \
        | grep -iE 'token|secret|password|passwd|nonce|salt|api[_-]?key' \
        | head -n $((MAX_PER_RULE * 4)) \
        | while IFS= read -r match; do
            local file rest line content snippet
            file="${match%%:*}"; rest="${match#*:}"
            line="${rest%%:*}"; content="${rest#*:}"
            snippet="$(trim_snippet "$content")"
            emit_finding "SEC.RANDOM.insecure-token" "medium" "$file" "$line" "$snippet"
        done
}

# SEC.TLS.verify-false
scan_verify_false() {
    scan_regex "SEC.TLS.verify-false" "high" 'verify[[:space:]]*=[[:space:]]*False'
}

# TYPE.ANY.any-annotation — `: Any` or `-> Any`
scan_any_annotation() {
    scan_regex "TYPE.ANY.any-annotation" "high" ':[[:space:]]*Any\b|->[[:space:]]*Any\b'
}

# TYPE.IGNORE.bare-type-ignore — `# type: ignore` with no [code]
scan_bare_type_ignore() {
    scan_regex "TYPE.IGNORE.bare-type-ignore" "high" '#[[:space:]]*type:[[:space:]]*ignore[[:space:]]*$'
}

# TYPE.CAST.cast-usage
scan_cast_usage() {
    scan_regex "TYPE.CAST.cast-usage" "low" '\bcast\('
}

# ERR.EXCEPT.bare-except
scan_bare_except() {
    scan_regex "ERR.EXCEPT.bare-except" "critical" 'except[[:space:]]*:'
}

# ERR.EXCEPT.except-pass — except ...: pass (same line or next line)
scan_except_pass() {
    scan_multiline "ERR.EXCEPT.except-pass" "high" \
        'except[^\n:]*:\s*(\n\s*)?pass\b'
}

# ERR.EXCEPT.broad-except
scan_broad_except() {
    scan_regex "ERR.EXCEPT.broad-except" "medium" 'except[[:space:]]+Exception\b'
}

# QUAL.PRINT.print-debug — print( at start of line, excluding cli/__main__ files
scan_print_debug() {
    rule_enabled "QUAL.PRINT.print-debug" || return 0
    [ "$FILES_SCANNED" -eq 0 ] && return 0
    local list="$WORKDIR/print_list.txt"
    grep -vE '(^|/)(cli|__main__|__init__)\.py$|(^|/)cli/' "$FILES_LIST" > "$list" || true
    [ ! -s "$list" ] && return 0
    < "$list" tr '\n' '\0' | xargs -0 -P "$PARALLEL" -n 50 \
        grep -HnE '^[[:space:]]*print\(' 2>/dev/null \
        | head -n $((MAX_PER_RULE * 4)) \
        | while IFS= read -r match; do
            local file rest line content snippet
            file="${match%%:*}"; rest="${match#*:}"
            line="${rest%%:*}"; content="${rest#*:}"
            snippet="$(trim_snippet "$content")"
            emit_finding "QUAL.PRINT.print-debug" "medium" "$file" "$line" "$snippet"
        done
}

# QUAL.IMPORT.wildcard-import
scan_wildcard_import() {
    scan_regex "QUAL.IMPORT.wildcard-import" "medium" '^from[[:space:]]+\S+[[:space:]]+import[[:space:]]+\*'
}

# QUAL.OSPATH.os-path
scan_os_path() {
    scan_regex "QUAL.OSPATH.os-path" "low" '\bos\.path\.'
}

# DATA.ENV.adhoc-environ — os.environ[...] subscripting (exclude settings/config/env modules)
scan_adhoc_environ() {
    rule_enabled "DATA.ENV.adhoc-environ" || return 0
    [ "$FILES_SCANNED" -eq 0 ] && return 0
    local list="$WORKDIR/environ_list.txt"
    grep -vE '(^|/)(settings|config|env|environment)\.py$|(^|/)(settings|config)/' "$FILES_LIST" > "$list" || true
    [ ! -s "$list" ] && return 0
    < "$list" tr '\n' '\0' | xargs -0 -P "$PARALLEL" -n 50 \
        grep -HnE 'os\.environ\[' 2>/dev/null \
        | head -n $((MAX_PER_RULE * 4)) \
        | while IFS= read -r match; do
            local file rest line content snippet
            file="${match%%:*}"; rest="${match#*:}"
            line="${rest%%:*}"; content="${rest#*:}"
            snippet="$(trim_snippet "$content")"
            emit_finding "DATA.ENV.adhoc-environ" "medium" "$file" "$line" "$snippet"
        done
}

# ARCH.IO.now-in-logic — datetime.now()/utcnow() outside tests
scan_now_in_logic() {
    scan_regex "ARCH.IO.now-in-logic" "low" 'datetime\.now\(|datetime\.utcnow\(' --exclude-tests
}

# PERF.CONCAT.str-concat-loop — best-effort: a `for ...:` followed by `+= "..."`
scan_str_concat_loop() {
    # Quote char matched as ["\x27] to avoid embedding a literal quote here.
    scan_multiline "PERF.CONCAT.str-concat-loop" "low" \
        'for\s+\w[^\n]*:\s*\n[^\n]*\+=[^\n]*["\x27]' --exclude-tests
}

# PKG.SETUP.legacy-setup — setup.py present alongside pyproject.toml
scan_legacy_setup() {
    rule_enabled "PKG.SETUP.legacy-setup" || return 0
    if [ -f "pyproject.toml" ] && [ -f "setup.py" ]; then
        scan_file_present "PKG.SETUP.legacy-setup" "low" "setup.py" \
            "setup.py present alongside pyproject.toml (metadata duplication)"
    elif [ -f "pyproject.toml" ] && [ -f "setup.cfg" ]; then
        scan_file_present "PKG.SETUP.legacy-setup" "low" "setup.cfg" \
            "setup.cfg present alongside pyproject.toml (metadata duplication)"
    fi
}

# TEST.ASSERTTRUE.assert-true
scan_assert_true() {
    scan_regex "TEST.ASSERTTRUE.assert-true" "low" 'assert[[:space:]]+True\b'
}

# ---------- Run all enabled rules ---------------------------------------------

scan_eval_exec
scan_shell_true
scan_pickle_loads
scan_yaml_load
scan_string_sql
scan_insecure_token
scan_verify_false
scan_any_annotation
scan_bare_type_ignore
scan_cast_usage
scan_bare_except
scan_except_pass
scan_broad_except
scan_print_debug
scan_wildcard_import
scan_os_path
scan_adhoc_environ
scan_now_in_logic
scan_str_concat_loop
scan_legacy_setup
scan_assert_true

# ---------- Determine exit code (any critical finding => 1) -------------------

HAS_CRITICAL=0
for f in "$FINDINGS_DIR"/*.ndjson; do
    [ -f "$f" ] || continue
    if grep -q '"severity": *"critical"' "$f" 2>/dev/null || grep -q '"severity":"critical"' "$f" 2>/dev/null; then
        HAS_CRITICAL=1
        break
    fi
done

# ---------- Render report -----------------------------------------------------

render() {
    if [ "$JSON_MODE" = true ]; then
        if has_cmd python3; then
            printf '%s\n' "${RULE_IDS[@]}"  > "$WORKDIR/ids.txt"
            printf '%s\n' "${RULE_META[@]}" > "$WORKDIR/meta.txt"

            SPECKIT_W="$WORKDIR" \
            SPECKIT_REPO_ROOT="$REPO_ROOT" \
            SPECKIT_FILES_SCANNED="$FILES_SCANNED" \
            SPECKIT_PATHS="$PATHS_ARG" \
            SPECKIT_MAX_PER_RULE="$MAX_PER_RULE" \
            SPECKIT_MIN_SEVERITY="$MIN_SEVERITY" \
            python3 <<'PY'
import datetime as dt, glob, json, os
w = os.environ["SPECKIT_W"]
ids   = [l.rstrip("\n") for l in open(os.path.join(w, "ids.txt"),  encoding="utf-8") if l.strip()]
metas = [l.rstrip("\n") for l in open(os.path.join(w, "meta.txt"), encoding="utf-8") if l.strip()]

rule_meta = {}
for rid, m in zip(ids, metas):
    sev, section, phase, directive, remediation = m.split("|", 4)
    rule_meta[rid] = {
        "id": rid, "severity": sev, "section": section, "phase": phase,
        "directive": directive, "remediation": remediation,
    }

findings = []
findings_dir = os.path.join(w, "findings")
for path in sorted(glob.glob(os.path.join(findings_dir, "*.ndjson"))):
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            rid = rec.get("rule_id")
            meta = rule_meta.get(rid, {})
            rec["section"]     = meta.get("section")
            rec["phase"]       = meta.get("phase")
            rec["directive"]   = meta.get("directive")
            rec["remediation"] = meta.get("remediation")
            findings.append(rec)

by_sev = {"critical": 0, "high": 0, "medium": 0, "low": 0}
by_section = {}
by_rule = {}
for fnd in findings:
    by_sev[fnd["severity"]] = by_sev.get(fnd["severity"], 0) + 1
    sec_key = (fnd.get("rule_id") or ".").split(".", 1)[0] or "unknown"
    by_section[sec_key] = by_section.get(sec_key, 0) + 1
    by_rule[fnd["rule_id"]] = by_rule.get(fnd["rule_id"], 0) + 1

paths = os.environ.get("SPECKIT_PATHS") or None
if paths:
    paths = [p for p in paths.split(",") if p]

result = {
    "schema_version": "1.0",
    "command": "audit",
    "scanned_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "repo_root": os.environ["SPECKIT_REPO_ROOT"],
    "scope": {
        "files_scanned":  int(os.environ["SPECKIT_FILES_SCANNED"]),
        "paths_included": paths,
        "extensions":     [".py", ".pyi"],
        "min_severity":   os.environ["SPECKIT_MIN_SEVERITY"],
        "max_per_rule":   int(os.environ["SPECKIT_MAX_PER_RULE"]),
    },
    "summary": {
        "rules_evaluated":     len(ids),
        "rules_with_findings": len(by_rule),
        "findings_total":      len(findings),
        "by_severity":         by_sev,
        "by_section":          by_section,
        "by_rule":             by_rule,
    },
    "rules":    list(rule_meta.values()),
    "findings": findings,
}
print(json.dumps(result, indent=2))
PY
        else
            echo '{"error":"python3 unavailable; cannot render JSON report"}'
        fi
    else
        echo "speckit audit — $REPO_ROOT"
        echo "Files scanned: $FILES_SCANNED"
        echo "Min severity:  $MIN_SEVERITY"
        echo ""
        local total=0 rule_id n
        for f in "$FINDINGS_DIR"/*.ndjson; do
            [ -f "$f" ] || continue
            [ -s "$f" ] || continue
            rule_id="$(basename "$f" .ndjson)"
            n="$(wc -l < "$f" | tr -d ' ')"
            total=$((total + n))
            printf '  %-40s %3d finding(s)\n' "$rule_id" "$n"
        done
        [ "$total" -eq 0 ] && echo "  (no findings)"
        echo ""
        echo "Total findings: $total"
    fi
}

if [ -n "$OUTPUT_FILE" ]; then
    render > "$OUTPUT_FILE"
    echo "[audit] Report written to $OUTPUT_FILE" >&2
else
    render
fi

exit "$HAS_CRITICAL"
