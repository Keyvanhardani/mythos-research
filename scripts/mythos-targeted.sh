#!/bin/bash
# =============================================================================
# mythos-targeted.sh — Hunt specific files directly (no sink ranking)
#
# Use case: you already know which files are high-value (public-facing
# controllers, share handlers, OCM endpoints). Skip Phase 1/2 and launch a
# hunter per file with higher budget + explicit "trust-boundary entry point"
# framing.
#
# Usage:
#   mythos-targeted.sh <target-dir> <files-list> [--budget USD] [--model M]
#
#   <files-list> is a text file with one RELATIVE path per line (relative to
#   <target-dir>), or "-" to read from stdin.
# =============================================================================

set -euo pipefail

TARGET_DIR=""
FILES_LIST=""
BUDGET="5.00"
MODEL="claude-opus-4-7"
SCAN_ID="targeted_$(date +%Y%m%d_%H%M%S)_$$"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_DIR="$BASE_DIR/reports/$SCAN_ID"
LOG_DIR="$BASE_DIR/logs/$SCAN_ID"
PROMPTS_DIR="$BASE_DIR/prompts"
LIB_DIR="$BASE_DIR/scripts/lib"

while [[ $# -gt 0 ]]; do
    case $1 in
        --budget) BUDGET="$2"; shift 2 ;;
        --model)  MODEL="$2"; shift 2 ;;
        --help|-h) sed -n '2,16p' "$0"; exit 0 ;;
        *)
            if   [ -z "$TARGET_DIR" ]; then TARGET_DIR="$1"
            elif [ -z "$FILES_LIST" ]; then FILES_LIST="$1"
            else echo "unexpected arg: $1" >&2; exit 1
            fi
            shift ;;
    esac
done

[ -z "$TARGET_DIR" ] && { echo "target-dir required" >&2; exit 1; }
[ -z "$FILES_LIST" ] && { echo "files-list required (or '-' for stdin)" >&2; exit 1; }
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

mkdir -p "$REPORT_DIR/findings" "$REPORT_DIR/validated" "$LOG_DIR"

# Detect dominant language for VSP prompt selection.
LANG_TAG=$("$LIB_DIR/detect-language.sh" "$TARGET_DIR" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["dominant"])')
case "$LANG_TAG" in
    php)    VSP="$PROMPTS_DIR/vsp-php.md" ;;
    python) VSP="$PROMPTS_DIR/vsp-python.md" ;;
    js-ts)  VSP="$PROMPTS_DIR/vsp-js-ts.md" ;;
    c-cpp)  VSP="$PROMPTS_DIR/vsp-c-cpp.md" ;;
    *)      VSP="$PROMPTS_DIR/vsp-analysis.md" ;;
esac

echo "=========================================================="
echo " mythos-targeted | $SCAN_ID"
echo " target  : $TARGET_DIR"
echo " lang    : $LANG_TAG  (prompt $(basename "$VSP"))"
echo " budget  : \$$BUDGET per hunter"
echo " report  : $REPORT_DIR"
echo "=========================================================="

HUNTER_MISSION=$(cat "$PROMPTS_DIR/hunter-agent.md")
VSP_BODY=$(cat "$VSP")

if [ "$FILES_LIST" = "-" ]; then
    mapfile -t FILES < <(grep -v '^#' | grep -v '^$')
else
    mapfile -t FILES < <(grep -v '^#' "$FILES_LIST" | grep -v '^$')
fi

extract_json_py() {
    cat <<'PY'
import json, re, sys, pathlib
log_path, out_path = sys.argv[1], sys.argv[2]
final_text = ""
for line in pathlib.Path(log_path).read_text(errors="replace").splitlines():
    line = line.strip()
    if not line or not line.startswith("{"):
        continue
    try: ev = json.loads(line)
    except Exception: continue
    if ev.get("type") == "result":
        final_text = ev.get("result", "") or ""
        break

def extract_json(text):
    if not text: return None
    for m in re.finditer(r"```(?:json)?\s*\n(.*?)\n```", text, flags=re.S):
        b = m.group(1).strip()
        if b.startswith("{"):
            try: return json.loads(b)
            except Exception: pass
    depth, end = 0, None
    for i in range(len(text)-1, -1, -1):
        c = text[i]
        if c == "}":
            if depth == 0: end = i + 1
            depth += 1
        elif c == "{":
            depth -= 1
            if depth == 0 and end is not None:
                try: return json.loads(text[i:end])
                except Exception:
                    end, depth = None, 0; continue
    return None

r = extract_json(final_text)
with open(out_path, "w") as f:
    json.dump(r or {"error":"no_json","raw_tail":final_text[-1500:]}, f, indent=2)
PY
}

hunt_one() {
    local rel="$1"
    local abs="$TARGET_DIR/$rel"
    if [ ! -f "$abs" ]; then
        echo "  ! missing: $rel" >&2
        return
    fi
    local slug=$(printf '%s' "$rel" | tr '/' '_' | tr -c 'A-Za-z0-9_.-' '_')
    local out="$REPORT_DIR/findings/${slug}.json"
    local log_file="$LOG_DIR/hunt_${slug}.log"

    local prompt
    prompt=$(cat <<PROMPT
$HUNTER_MISSION

---

## Language-specific taxonomy

$VSP_BODY

---

## Target for this run — an entry-point / trust-boundary file

**Project root (cwd):** \`$TARGET_DIR\`
**Primary file under investigation:** \`$rel\`

This file was selected **because it is a trust-boundary entry point** (public
controller, public-share endpoint, cross-instance federation API, or similar).
Unlike a random file, this one almost certainly handles attacker-controlled
input. Your job is to trace every request-derived value through the file and
find a place where access control, sanitization, or scoping is missing.

**Explicit angles to check:**
- Every public method = an HTTP route. Which routes are \`@PublicPage\` /
  \`@NoCSRFRequired\` / \`@AnonRateThrottle\` annotated? Those are unauth.
- For each request parameter (body, query, URL, header), trace it through
  method → service → sink. Is there an \`isAdmin\` / \`canAccess\` /
  \`ownershipCheck\` call on the path? If not, you likely have IDOR.
- Share-token handling: does the code revalidate the token against the
  actual target resource, or does it trust any token that decodes?
- File access via path parameter: is there a prefix-check against the
  user's home, or only a \`../\` string-strip?
- Any \`new URL()\` / \`fopen(\$url)\` / \`curl\` on a user-supplied URL: is
  private-IP/metadata-endpoint blocked? → SSRF candidate.

Use Grep to find the route definition(s) pointing at this class (grep
\`appinfo/routes.php\` and \`@route\`). Use Read for any service class the
controller injects. Do not stop at the controller — follow the data.

Output strict JSON per the hunter-agent spec. Report ONLY HIGH or CRITICAL.
PROMPT
)

    (
        cd "$TARGET_DIR"
        printf '%s' "$prompt" | claude -p \
            --model "$MODEL" \
            --output-format stream-json \
            --include-partial-messages \
            --verbose \
            --input-format text \
            --allowed-tools "Read" "Grep" "Glob" \
            --disallowed-tools "Bash" "Edit" "Write" "NotebookEdit" "WebFetch" "WebSearch" \
            --add-dir "$TARGET_DIR" \
            --permission-mode bypassPermissions \
            --max-turns 60 \
            --max-budget-usd "$BUDGET" \
            > "$log_file" 2>&1
    ) || true

    python3 - "$log_file" "$out" <<<"$(extract_json_py)" || true
    printf '  ✓ %s\n' "$rel"
}

PIDS=()
for rel in "${FILES[@]}"; do
    [ -z "$rel" ] && continue
    echo "  launch : $rel"
    hunt_one "$rel" &
    PIDS+=($!)
done

DONE=0
for pid in "${PIDS[@]}"; do
    wait "$pid" || true
    DONE=$((DONE + 1))
    echo "  progress $DONE/${#PIDS[@]}"
done

echo "Phase: aggregate"
python3 - <<PY > "$REPORT_DIR/summary.json"
import json, pathlib, collections
rd = pathlib.Path("$REPORT_DIR")
findings = []
for f in sorted((rd / "findings").glob("*.json")):
    try: d = json.loads(f.read_text())
    except Exception: continue
    for fnd in (d.get("findings") or []):
        fnd["_source_file"] = f.name
        findings.append(fnd)
sev = collections.Counter(f.get("severity","UNKNOWN") for f in findings)
print(json.dumps({
    "scan_id": "$SCAN_ID",
    "target":  "$TARGET_DIR",
    "language": "$LANG_TAG",
    "model":   "$MODEL",
    "hunter_findings": len(findings),
    "severity_breakdown": dict(sev),
    "findings": findings,
}, indent=2))
PY

echo "=========================================================="
echo "  DONE — $REPORT_DIR/summary.json"
echo "=========================================================="
