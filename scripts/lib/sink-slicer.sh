#!/bin/bash
# =============================================================================
# sink-slicer.sh — Grep for dangerous sinks and emit an NDJSON bundle.
# Usage:  sink-slicer.sh <target-dir> <language> <output-dir>
#   language ∈ {php, python, js-ts, c-cpp}
#
# Output:
#   <output-dir>/sinks.ndjson      — one hit per line, JSON
#   <output-dir>/sinks.summary.txt — human-readable counts
#   <output-dir>/top-files.txt     — files ranked by sink density
# =============================================================================

set -euo pipefail

TARGET="${1:?Usage: sink-slicer.sh <target-dir> <language> <output-dir>}"
LANG_TAG="${2:?language required: php|python|js-ts|c-cpp}"
OUT="${3:?output dir required}"
LIB_DIR="$(cd "$(dirname "$0")" && pwd)"

SINK_FILE="$LIB_DIR/sinks/${LANG_TAG}.txt"
if [ ! -f "$SINK_FILE" ]; then
    echo "No sink list for language: $LANG_TAG (expected $SINK_FILE)" >&2
    exit 1
fi

# Resolve ripgrep binary (shell aliases don't expand in non-interactive scripts).
if command -v rg >/dev/null 2>&1; then
    RG="$(command -v rg)"
else
    # Try to locate any bundled rg in a claude-code install.
    RG="$(find /home /usr /opt -type f -name rg -executable 2>/dev/null | grep -m1 ripgrep)"
fi
if [ -z "${RG:-}" ] || [ ! -x "$RG" ]; then
    echo "ripgrep (rg) not found on PATH. Install it (apt install ripgrep)." >&2
    exit 1
fi

case "$LANG_TAG" in
    php)    GLOB_ARGS=(-g "*.php" -g "*.phtml" -g "*.inc") ;;
    python) GLOB_ARGS=(-g "*.py") ;;
    js-ts)  GLOB_ARGS=(-g "*.js" -g "*.mjs" -g "*.cjs" -g "*.ts" -g "*.tsx" -g "*.jsx") ;;
    c-cpp)  GLOB_ARGS=(-g "*.c" -g "*.h" -g "*.cpp" -g "*.cc" -g "*.hpp" -g "*.cxx") ;;
    *)      echo "unknown language: $LANG_TAG" >&2; exit 1 ;;
esac

RG_EXCLUDE=(
    -g '!**/node_modules/**' -g '!**/vendor/**'
    -g '!**/3rdparty/**' -g '!**/third_party/**'
    -g '!**/dist/**' -g '!**/build/**'
    -g '!**/.venv/**' -g '!**/__pycache__/**'
    -g '!**/*.min.js' -g '!**/*.min.css'
    -g '!**/tests/**' -g '!**/test/**' -g '!**/__tests__/**'
    -g '!**/*.test.*' -g '!**/*.spec.*'
    -g '!**/fixtures/**'
    # Composer/NPM/Python auto-generated metadata inside per-app vendor trees.
    -g '!**/composer/**'
    -g '!**/InstalledVersions.php'
    -g '!**/autoload*.php'
    -g '!**/autoload*.js'
    -g '!**/site-packages/**'
    # Common vendored JS bundles that hide inside public/ directories. These
    # match ExtJS-style admin-UI vendor bundles (jQuery, Bootstrap, etc.)'s ExtJS 152k-line vendor bundles
    # which previously dominated tier A of the ranker. Also jquery / bootstrap
    # / moment / lodash / d3 / codemirror / angular / react / vue bundles that
    # ship in wp-admin-like front-ends.
    -g '!**/public/**/extjs/**'
    -g '!**/public/**/ext-all*'
    -g '!**/public/**/jquery*'
    -g '!**/public/**/bootstrap*'
    -g '!**/public/**/moment*'
    -g '!**/public/**/lodash*'
    -g '!**/public/**/d3*'
    -g '!**/public/**/codemirror*'
    -g '!**/public/**/angular*'
    -g '!**/public/**/react*'
    -g '!**/public/**/vue*'
    -g '!**/assets/**/*.bundle.js'
    -g '!**/static/**/*.bundle.js'
    -g '!**/wp-includes/js/**'
    -g '!**/*.pack.js'
    -g '!**/*-bundle.js'
)

mkdir -p "$OUT"
: > "$OUT/sinks.ndjson"

while IFS=$'\t' read -r category pattern; do
    [[ -z "${category// }" || "${category}" =~ ^# ]] && continue
    [[ -z "${pattern// }" ]] && continue
    "$RG" --json --pcre2 --no-ignore-vcs \
        --hidden --follow \
        "${GLOB_ARGS[@]}" "${RG_EXCLUDE[@]}" \
        -e "$pattern" "$TARGET" 2>/dev/null \
    | python3 -c '
import json, sys, pathlib
cat = sys.argv[1]
pat = sys.argv[2]
_FILE_CACHE = {}
def get_lines(path):
    if path not in _FILE_CACHE:
        try:
            _FILE_CACHE[path] = pathlib.Path(path).read_text(errors="replace").splitlines()
        except Exception:
            _FILE_CACHE[path] = []
    return _FILE_CACHE[path]

for line in sys.stdin:
    try:
        ev = json.loads(line)
    except Exception:
        continue
    if ev.get("type") != "match":
        continue
    d = ev["data"]
    path = d["path"].get("text")
    lineno = d.get("line_number")
    # Grab the hit line plus the next two, so multi-line calls like
    # unserialize($x,\n  ["allowed_classes" => [...]]) are visible.
    lines = get_lines(path)
    snippet_lines = lines[max(0, lineno - 1): lineno + 2] if lines else []
    snippet = " ".join(s.strip() for s in snippet_lines)[:400]
    if not snippet:
        snippet = d["lines"].get("text", "").rstrip()[:400]
    out = {
        "category": cat,
        "pattern":  pat,
        "file":     path,
        "line":     lineno,
        "snippet":  snippet,
    }
    print(json.dumps(out, ensure_ascii=False))
' "$category" "$pattern" >> "$OUT/sinks.ndjson" || true
done < "$SINK_FILE"

total_hits=$(wc -l < "$OUT/sinks.ndjson" | tr -d ' ')

python3 - <<PY
import json, collections, pathlib
p = pathlib.Path("$OUT/sinks.ndjson")
by_cat = collections.Counter()
by_file = collections.Counter()
by_file_cats = collections.defaultdict(set)
total = 0
for line in p.read_text().splitlines():
    if not line.strip():
        continue
    try:
        ev = json.loads(line)
    except Exception:
        continue
    total += 1
    by_cat[ev["category"]] += 1
    by_file[ev["file"]] += 1
    by_file_cats[ev["file"]].add(ev["category"])

summary = pathlib.Path("$OUT/sinks.summary.txt")
with summary.open("w") as f:
    f.write(f"Total sink hits: {total}\n")
    f.write(f"Files with >=1 sink: {len(by_file)}\n\n")
    f.write("Hits per category:\n")
    for cat, n in by_cat.most_common():
        f.write(f"  {n:6d}  {cat}\n")

topf = pathlib.Path("$OUT/top-files.txt")
with topf.open("w") as f:
    for path, n in by_file.most_common(100):
        cats = ",".join(sorted(by_file_cats[path]))
        f.write(f"{n:4d}\t{path}\t{cats}\n")
PY

echo "sink-slicer: $total_hits hits → $OUT/" >&2
