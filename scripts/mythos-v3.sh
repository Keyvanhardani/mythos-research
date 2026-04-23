#!/bin/bash
# =============================================================================
# mythos-v3.sh — Agentic orchestrator with live-exec + diversity seeds
#
# New in v3 over v2:
#   - Phase 3 hunters get a per-run diversity focus hint (different aspect of
#     the same file when --pass-at-k > 1)
#   - Phase 5 [NEW]: live-exec validation via scripts/exec-validator.sh for
#     every HIGH / CRITICAL finding — produces a real PoC against the live
#     install and returns crash/marker/asan evidence
#   - Cost telemetry per phase in summary.json
#
# Pipeline:
#   Phase 0: Language detection
#   Phase 1: Sink-guided slicing
#   Phase 2: File ranking (sink density × language heuristic)
#   Phase 3: Parallel agentic hunter per top file (+diversity for pass@k)
#   Phase 4: Skeptical source validator
#   Phase 5: LIVE-EXEC validator for HIGH/CRITICAL findings   [NEW]
#   Phase 6: Aggregate + summary
#
# Usage:
#   mythos-v3.sh <target-dir> [--max-files N] [--budget USD] [--language X]
#                             [--pass-at-k K] [--min-exec-severity HIGH|MEDIUM]
#                             [--skip-exec] [--model MODEL]
#
# Design doc: scripts/V3_DESIGN.md
# =============================================================================

set -euo pipefail

# --- Defaults ---
TARGET_DIR=""
MAX_FILES=8
BUDGET_PER_RUN="3.00"
LANG_OVERRIDE=""
MODEL="claude-opus-4-7"
BACKEND="claude"     # claude | qwen
QWEN_ENDPOINT="${HUNTER_ENDPOINT:-http://localhost:5000/api/chat}"

# Research Edition: live-exec validator is held private. If scripts/exec-validator.sh
# is not present, Phase 5 is automatically skipped with a clear notice.
EXEC_VALIDATOR="$(dirname "$0")/exec-validator.sh"
QWEN_MODEL="${HUNTER_MODEL:-qwen3-coder}"
PASS_AT_K=1                          # v3: K runs per file with diverse focus
MIN_EXEC_SEVERITY="HIGH"             # v3: what severity triggers exec-validator
SKIP_EXEC=0                          # v3: --skip-exec to behave like v2
EXEC_BUDGET="3.00"                   # v3: per-finding budget for exec-validator
EXEC_MAX_CONCURRENT="2"              # v3: concurrent exec-validator jobs
EXEC_MAX_TURNS="50"                  # v3: max turns for exec-validator agent
SCAN_ID="mythos3_$(date +%Y%m%d_%H%M%S)_$$"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_DIR="$BASE_DIR/reports/$SCAN_ID"
LOG_DIR="$BASE_DIR/logs/$SCAN_ID"
PROMPTS_DIR="$BASE_DIR/prompts"
LIB_DIR="$BASE_DIR/scripts/lib"

while [[ $# -gt 0 ]]; do
    case $1 in
        --max-files) MAX_FILES="$2"; shift 2 ;;
        --budget)    BUDGET_PER_RUN="$2"; shift 2 ;;
        --language)  LANG_OVERRIDE="$2"; shift 2 ;;
        --model)     MODEL="$2"; shift 2 ;;
        --backend)   BACKEND="$2"; shift 2 ;;
        --qwen-endpoint) QWEN_ENDPOINT="$2"; shift 2 ;;
        --qwen-model)    QWEN_MODEL="$2"; shift 2 ;;
        --pass-at-k)          PASS_AT_K="$2"; shift 2 ;;
        --min-exec-severity)  MIN_EXEC_SEVERITY="$2"; shift 2 ;;
        --skip-exec)          SKIP_EXEC=1; shift ;;
        --exec-budget)        EXEC_BUDGET="$2"; shift 2 ;;
        --exec-max-concurrent) EXEC_MAX_CONCURRENT="$2"; shift 2 ;;
        --exec-max-turns)     EXEC_MAX_TURNS="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,26p' "$0"; exit 0 ;;
        *)
            if [ -z "$TARGET_DIR" ]; then TARGET_DIR="$1"; else
                echo "unexpected arg: $1" >&2; exit 1
            fi
            shift ;;
    esac
done

if [ -z "$TARGET_DIR" ]; then
    echo "Error: target directory required" >&2
    echo "Usage: mythos-v3.sh <target-dir> [--max-files N] [--budget USD] [--language X]" >&2
    exit 1
fi
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

mkdir -p "$REPORT_DIR"/{findings,validated,slices} "$LOG_DIR"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
jlog() {
    local type="$1"; shift
    local msg="$*"
    printf '{"ts":"%s","scan_id":"%s","type":"%s","msg":%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$SCAN_ID" "$type" \
        "$(printf '%s' "$msg" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))')" \
        >> "$LOG_DIR/events.jsonl"
}

echo "=========================================================="
echo "  mythos-v3 |  scan $SCAN_ID"
echo " target : $TARGET_DIR"
echo " model  : $MODEL"
echo " budget : \$$BUDGET_PER_RUN per hunter, max $MAX_FILES hunters"
echo " report : $REPORT_DIR"
echo "=========================================================="

jlog "scan_start" "target=$TARGET_DIR max_files=$MAX_FILES budget=$BUDGET_PER_RUN model=$MODEL"

# =============================================================================
# PHASE 0: Language detection
# =============================================================================
log "Phase 0 — language detection"
"$LIB_DIR/detect-language.sh" "$TARGET_DIR" > "$REPORT_DIR/language.json"

if [ -n "$LANG_OVERRIDE" ]; then
    LANG_TAG="$LANG_OVERRIDE"
else
    LANG_TAG=$(python3 -c 'import json,sys; print(json.load(open("'"$REPORT_DIR"'/language.json"))["dominant"])')
fi

# Map dominant → VSP prompt file
case "$LANG_TAG" in
    php)     VSP_PROMPT="$PROMPTS_DIR/vsp-php.md" ;;
    python)  VSP_PROMPT="$PROMPTS_DIR/vsp-python.md" ;;
    js-ts|js|ts)
        LANG_TAG="js-ts"
        VSP_PROMPT="$PROMPTS_DIR/vsp-js-ts.md" ;;
    c-cpp|c|cpp)
        LANG_TAG="c-cpp"
        VSP_PROMPT="$PROMPTS_DIR/vsp-c-cpp.md" ;;
    *)
        echo "No VSP prompt for language '$LANG_TAG' — falling back to generic VSP" >&2
        VSP_PROMPT="$PROMPTS_DIR/vsp-analysis.md"
        ;;
esac

log "  detected: $LANG_TAG  (prompt: $(basename "$VSP_PROMPT"))"
jlog "language" "$LANG_TAG"

# =============================================================================
# PHASE 1: Sink slicing
# =============================================================================
log "Phase 1 — sink slicing"
"$LIB_DIR/sink-slicer.sh" "$TARGET_DIR" "$LANG_TAG" "$REPORT_DIR/slices" 2>&1 | tee -a "$LOG_DIR/slicer.log" >&2

SINK_HITS=$(wc -l < "$REPORT_DIR/slices/sinks.ndjson" | tr -d ' ')
log "  $SINK_HITS sink hits"
jlog "sinks" "hits=$SINK_HITS"

if [ "$SINK_HITS" -eq 0 ]; then
    echo "No sinks found — nothing to hunt. Exit." >&2
    exit 0
fi

# =============================================================================
# PHASE 2: File ranking (sink-density + recency bonus)
# =============================================================================
log "Phase 2 — file ranking"

python3 - <<PY > "$REPORT_DIR/ranked-files.txt"
import json, collections, pathlib, re
slice_path = pathlib.Path("$REPORT_DIR/slices/sinks.ndjson")
cats_per_file = collections.defaultdict(set)

# Snippet-level "obviously safe" patterns. When present, the hit is downgraded
# from tier A to tier C (still visible, but no longer driving the rank).
SAFE_PATTERNS = {
    "OBJECT_INJECTION": re.compile(r"allowed_classes", re.I),
    "DESERIALIZE":      re.compile(r"(SafeLoader|allowed_modules|filter\s*=\s*['\"]data['\"])", re.I),
    "CODE_EVAL":        re.compile(r"(ast\.literal_eval|literal_eval|assert\s*\(\s*['\"])", re.I),
    "XXE":              re.compile(r"(libxml_disable_entity_loader|defusedxml|resolve_entities\s*=\s*False)", re.I),
    "SQL_INJECTION":    re.compile(r"(->\s*prepare\s*\(|\?|:[a-zA-Z_])", re.I),
}

# Tier A — always rank these files first. Rare categories, high historical
# vuln-yield, hard to reach by accident. v3.1 adds SANITIZER_REVIEW (function
# definitions that warrant semantic hunter review) and BROWSER_API_FOOTGUN
# (Chrome extension webRequest sanitizer gaps).
TIER_A = {"OBJECT_INJECTION", "DESERIALIZE",
          "CODE_EVAL", "TEMPLATE_INJECT",
          "PROTOTYPE_POLLUTION", "XXE",
          "SQL_INJECTION", "NOSQL_INJECTION",
          "LIVESTATUS_INJECT",
          "DYNAMIC_REQUIRE",
          "SANITIZER_REVIEW",
          "BROWSER_API_FOOTGUN",
          "FRAMEWORK_FOOTGUN"}
# Tier B — common, noisy, but still interesting when input is reachable.
TIER_B = {"COMMAND_EXEC", "DYNAMIC_INCLUDE", "SSRF",
          "CALLBACK_INJECTION", "VAR_INJECTION",
          "ZIP_SLIP", "PATH_TRAVERSAL",
          "HEADER_INJECTION", "XSS_RAW", "XSS",
          "REDOS", "OPEN_REDIRECT",
          "WEAK_JWT", "WEAK_CRYPTO",
          "FORMAT_STRING", "ALLOC_COMPUTED",
          "MEMORY_UNCHECKED"}
# Everything else implicitly tier C.

count_a = collections.Counter()
count_b = collections.Counter()
count_c = collections.Counter()

for line in slice_path.read_text().splitlines():
    if not line.strip():
        continue
    ev = json.loads(line)
    f, c, snip = ev["file"], ev["category"], ev.get("snippet", "")
    # Demote hits that look obviously sanitized at the call-site.
    safe_re = SAFE_PATTERNS.get(c)
    if safe_re and safe_re.search(snip):
        count_c[f] += 1
        continue
    cats_per_file[f].add(c)
    if c in TIER_A:
        count_a[f] += 1
    elif c in TIER_B:
        count_b[f] += 1
    else:
        count_c[f] += 1

def _is_likely_vendor(path):
    import re, pathlib as _pl
    # normalise path separators without using a bash-escaped literal
    p = path
    if "/" not in p and "\\\\" in repr(p):
        p = p.replace(chr(92), "/")
    p = p.lower()
    if re.search(r"/(public|static|assets)/.*\.(js|ts)$", p):
        if count_a[path] + count_b[path] >= 30:
            return True
    for tok in ("ext-all", "jquery", "bootstrap", "codemirror", "lodash",
                "moment", "angular", ".min.", "-bundle", ".bundle.", ".pack."):
        if tok in p:
            return True
    try:
        if _pl.Path(path).exists():
            if _pl.Path(path).stat().st_size > 500_000:
                return True
    except Exception:
        pass
    return False

def key(f):
    distinct_a = len(cats_per_file[f] & TIER_A)
    vendor_penalty = 1 if _is_likely_vendor(f) else 0
    return (
        vendor_penalty,    # push vendored bundles to the back
        -distinct_a,       # files touching any tier-A sink first
        -count_a[f],
        -len(cats_per_file[f] & TIER_B),
        -count_b[f],
        -count_c[f],
        f,
    )

ordered = sorted(cats_per_file, key=key)
for path in ordered[: $MAX_FILES * 4]:
    a = sorted(cats_per_file[path] & TIER_A)
    b = sorted(cats_per_file[path] & TIER_B)
    all_cats = ",".join(sorted(cats_per_file[path]))
    tier = "A" if a else ("B" if b else "C")
    total = count_a[path] + count_b[path] + count_c[path]
    print(f"{tier}\t{total}\t{path}\t{all_cats}")
PY

# Cut to MAX_FILES but skip files that are >2500 lines (hunter can still Read them, but
# we do not want one mega-file hoarding all attention).
TOP_FILES=$(head -"$MAX_FILES" "$REPORT_DIR/ranked-files.txt" | cut -f3)
SELECTED=$(printf '%s\n' "$TOP_FILES" | grep -c . || echo 0)
log "  selected $SELECTED files"
jlog "ranking_done" "selected=$SELECTED"

if [ "$SELECTED" -eq 0 ]; then
    echo "No files ranked — exit." >&2
    exit 0
fi

# =============================================================================
# PHASE 3: Agentic hunt — one subagent per top file, with tool access
# =============================================================================
log "Phase 3 — agentic hunt (parallel)"

HUNTER_MISSION=$(cat "$PROMPTS_DIR/hunter-agent.md")
VSP_BODY=$(cat "$VSP_PROMPT")

# Build per-file sink slices so the hunter starts with a curated entry-point list.
build_slice_for_file() {
    local file="$1"
    python3 - "$REPORT_DIR/slices/sinks.ndjson" "$file" <<'PY'
import json, sys, collections
ndjson, target = sys.argv[1], sys.argv[2]
hits = []
for line in open(ndjson):
    if not line.strip():
        continue
    ev = json.loads(line)
    if ev["file"] == target:
        hits.append(ev)
hits.sort(key=lambda h: h["line"])
for h in hits:
    print(f"  L{h['line']:<5} {h['category']:<22} {h['snippet'].strip()[:120]}")
PY
}

# v3: pick a diversity focus hint for run K of a file — uses distinct sink
# categories present in the file as the source of variation. Returns empty
# string for k=1 (default / no hint) to preserve v2 behavior on pass-at-k=1.
pick_focus_hint() {
    local file="$1"
    local k="$2"
    [ "$k" -le 1 ] && { echo ""; return; }
    python3 - "$REPORT_DIR/slices/sinks.ndjson" "$file" "$k" <<'PY'
import json, sys, collections
ndjson, target, k = sys.argv[1], sys.argv[2], int(sys.argv[3])
cats = collections.Counter()
fn_like = collections.Counter()
for line in open(ndjson):
    if not line.strip(): continue
    ev = json.loads(line)
    if ev.get("file") != target: continue
    cats[ev.get("category","?")] += 1
    snip = ev.get("snippet","")
    # crude entry-point name grab: words before `(` that look function-ish
    import re
    for m in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_]{5,})\s*\(", snip):
        fn_like[m.group(1)] += 1
cats_list = [c for c,_ in cats.most_common()]
fns_list  = [f for f,_ in fn_like.most_common()]
hints = []
if cats_list: hints.append(f"Focus on the **{cats_list[(k-2) % len(cats_list)]}** sink category in this file")
if fns_list:  hints.append(f"Trace inputs that reach **{fns_list[(k-2) % len(fns_list)]}**")
print(" / ".join(hints) if hints else "Look for a bug class you haven't seen in this file yet")
PY
}

hunt_file() {
    local file="$1"
    local run_idx="${2:-1}"
    local focus_hint="${3:-}"
    local rel="${file#$TARGET_DIR/}"
    local slug=$(printf '%s' "$rel" | tr '/' '_' | tr -c 'A-Za-z0-9_.-' '_')
    if [ "$run_idx" -gt 1 ]; then slug="${slug}__k${run_idx}"; fi
    local out="$REPORT_DIR/findings/${slug}.json"
    local log_file="$LOG_DIR/hunt_${slug}.log"

    local slice
    slice=$(build_slice_for_file "$file")

    local focus_block=""
    if [ -n "$focus_hint" ]; then
        focus_block="

## Focus for this run (diversity hint)

${focus_hint}. Explicitly avoid re-analyzing areas that a parallel-run hunter would
cover; divergent focus is intentional.
"
    fi

    local prompt
    prompt=$(cat <<PROMPT
$HUNTER_MISSION

---

## Language-specific taxonomy

$VSP_BODY

---

## Target for this run

**Project root (cwd):** \`$TARGET_DIR\`
**Primary file under investigation:** \`$rel\`
$focus_block
## Pre-computed sinks in this file

$slice

These are grep hits. They are **candidates**, not confirmed bugs. Pick the most promising category
(object injection / code-eval / command-exec > others), trace input sources backwards with Grep,
then issue a final strict-JSON verdict per the format spec above.
PROMPT
)

    # --bare keeps the hunter isolated (no CLAUDE.md inheritance, no hooks).
    # --add-dir grants Read/Grep/Glob access to the target tree.
    # --permission-mode bypassPermissions lets the agent invoke tools unattended.
    # --disallowedTools keeps it strictly read-only (no Bash / Edit / Write).
    if [ "$BACKEND" = "qwen" ]; then
        (
            cd "$TARGET_DIR"
            printf '%s' "$prompt" | python3 "$LIB_DIR/hunter-qwen.py" \
                --endpoint "$QWEN_ENDPOINT" \
                --model "$QWEN_MODEL" \
                --target-dir "$TARGET_DIR" \
                --trace "$log_file.trace" \
                > "$log_file" 2>&1
        ) || true
    else
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
                --max-turns 40 \
                --max-budget-usd "$BUDGET_PER_RUN" \
                > "$log_file" 2>&1
        ) || true
    fi

    # Extract final "result" field (last assistant message) from stream-json log.
    # For backend=qwen, the log file contains a single JSON verdict object directly.
    python3 - "$log_file" "$out" <<'PY' || true
import json, re, sys, pathlib
log_path, out_path = sys.argv[1], sys.argv[2]
final_text = ""
raw = pathlib.Path(log_path).read_text(errors="replace").strip()
# Qwen hunter output path: entire log IS the verdict JSON on one (or a few) lines.
try:
    direct = json.loads(raw)
    if isinstance(direct, dict) and ("findings" in direct or "verdict" in direct):
        final_text = raw
except Exception:
    pass
# Claude stream-json path: walk events.
if not final_text:
    for line in raw.splitlines():
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except Exception:
            continue
        if ev.get("type") == "result":
            final_text = ev.get("result", "") or ""
            break
        if ev.get("type") == "assistant" and "message" in ev:
            for block in ev["message"].get("content", []):
                if block.get("type") == "text":
                    final_text = block.get("text", "") or final_text

def extract_json(text):
    if not text:
        return None
    # 1) ```json ... ``` fenced block (greedy to the last closing fence)
    for m in re.finditer(r"```(?:json)?\s*\n(.*?)\n```", text, flags=re.S):
        blob = m.group(1).strip()
        if blob.startswith("{"):
            try:
                return json.loads(blob)
            except Exception:
                pass
    # 2) Last balanced {...} object in the text
    depth = 0
    end = None
    for i in range(len(text) - 1, -1, -1):
        c = text[i]
        if c == "}":
            if depth == 0:
                end = i + 1
            depth += 1
        elif c == "{":
            depth -= 1
            if depth == 0 and end is not None:
                candidate = text[i:end]
                try:
                    return json.loads(candidate)
                except Exception:
                    end = None
                    depth = 0
                    continue
    # 3) Fallback: original rfind walk
    start = text.rfind("{")
    while start != -1:
        try:
            return json.loads(text[start:])
        except Exception:
            start = text.rfind("{", 0, start)
    return None

json_out = extract_json(final_text)

with open(out_path, "w") as f:
    if json_out is not None:
        json.dump(json_out, f, indent=2)
    else:
        json.dump({"error": "no_parseable_json", "raw_tail": final_text[-2000:]}, f, indent=2)
PY

    jlog "hunt_done" "file=$rel"
    printf '  ✓ %s\n' "$rel"
}

PIDS=()
INDEX=0
TOTAL_RUNS=$((SELECTED * PASS_AT_K))
while IFS= read -r file; do
    [ -z "$file" ] && continue
    INDEX=$((INDEX + 1))
    # v3: launch PASS_AT_K runs per file with different focus hints
    for k in $(seq 1 "$PASS_AT_K"); do
        hint=$(pick_focus_hint "$file" "$k")
        log "  launch $INDEX/$SELECTED k=$k/$PASS_AT_K : ${file#$TARGET_DIR/} ${hint:+[hint: ${hint:0:80}]}"
        jlog "hunt_start" "file=${file#$TARGET_DIR/} k=$k hint=$hint"
        hunt_file "$file" "$k" "$hint" &
        PIDS+=($!)
    done
done <<< "$TOP_FILES"

DONE=0
for pid in "${PIDS[@]}"; do
    wait "$pid" || true
    DONE=$((DONE + 1))
    log "  progress $DONE/$TOTAL_RUNS hunters complete"
done

# =============================================================================
# PHASE 4: Validation
# =============================================================================
log "Phase 4 — validation"
VALIDATION_PROMPT=$(cat "$PROMPTS_DIR/validation.md")

validate_finding() {
    local f="$1"
    local slug=$(basename "$f" .json)
    local out="$REPORT_DIR/validated/${slug}.json"
    local log_file="$LOG_DIR/val_${slug}.log"

    # Skip empties / errors / clean verdicts.
    if ! grep -q '"findings"' "$f" 2>/dev/null; then return 0; fi
    if grep -q '"verdict"\s*:\s*"CLEAN"' "$f" 2>/dev/null; then return 0; fi

    local finding_content
    finding_content=$(cat "$f")

    local prompt
    prompt=$(cat <<PROMPT
$VALIDATION_PROMPT

You have Read/Grep/Glob tool access to the actual source tree under \`$TARGET_DIR\`.
**Verify every file:line claim against the live code.** If a cited line does not
contain what the report says, mark it FALSE_POSITIVE.

--- HUNTER REPORT TO VERIFY ---
$finding_content
--- END REPORT ---

Output strict JSON: {"validated":[{...}]} — no prose outside the JSON.
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
            --max-turns 20 \
            --max-budget-usd "$BUDGET_PER_RUN" \
            > "$log_file" 2>&1
    ) || true

    python3 - "$log_file" "$out" <<'PY' || true
import json, sys, pathlib
log_path, out_path = sys.argv[1], sys.argv[2]
final_text = ""
for line in pathlib.Path(log_path).read_text(errors="replace").splitlines():
    line = line.strip()
    if not line or not line.startswith("{"):
        continue
    try:
        ev = json.loads(line)
    except Exception:
        continue
    if ev.get("type") == "result":
        final_text = ev.get("result", "") or ""
        break
    if ev.get("type") == "assistant" and "message" in ev:
        for block in ev["message"].get("content", []):
            if block.get("type") == "text":
                final_text = block.get("text", "") or final_text

json_out = None
if final_text:
    start = final_text.rfind("{")
    while start != -1:
        try:
            json_out = json.loads(final_text[start:])
            break
        except Exception:
            start = final_text.rfind("{", 0, start)

with open(out_path, "w") as f:
    if json_out is not None:
        json.dump(json_out, f, indent=2)
    else:
        json.dump({"error": "no_parseable_json", "raw_tail": final_text[-2000:]}, f, indent=2)
PY
    jlog "val_done" "file=$slug"
    printf '  ✓ validated %s\n' "$slug"
}

VPIDS=()
for f in "$REPORT_DIR"/findings/*.json; do
    [ -f "$f" ] || continue
    validate_finding "$f" &
    VPIDS+=($!)
done
for pid in "${VPIDS[@]}"; do wait "$pid" || true; done

# =============================================================================
# PHASE 5 [v3-NEW]: LIVE-EXEC VALIDATION for HIGH/CRITICAL findings
# =============================================================================
if [ "$SKIP_EXEC" = "1" ]; then
    log "Phase 5 — SKIPPED (--skip-exec)"
    jlog "exec_skipped" "reason=--skip-exec"
else
    log "Phase 5 — live-exec validation (min-severity=$MIN_EXEC_SEVERITY)"
    jlog "exec_start" "min_severity=$MIN_EXEC_SEVERITY budget=$EXEC_BUDGET concurrent=$EXEC_MAX_CONCURRENT"

    EXEC_SCRIPT="$BASE_DIR/scripts/exec-validator.sh"
    if [ ! -x "$EXEC_SCRIPT" ]; then
        log "  WARN: exec-validator.sh missing or not executable; skipping phase 5"
        jlog "exec_skipped" "reason=no_exec_validator_script"
    else
        MYTHOS_EXPLOIT="$BASE_DIR/scripts/mythos-exploit.sh"
        if [ ! -x "$MYTHOS_EXPLOIT" ]; then
            log "  WARN: mythos-exploit.sh missing; skipping phase 5"
            jlog "exec_skipped" "reason=no_mythos_exploit_script"
        else
            bash "$MYTHOS_EXPLOIT" "$REPORT_DIR" "$TARGET_DIR" \
                --min-severity "$MIN_EXEC_SEVERITY" \
                --budget "$EXEC_BUDGET" \
                --max-concurrent "$EXEC_MAX_CONCURRENT" \
                --max-turns "$EXEC_MAX_TURNS" 2>&1 | tee -a "$LOG_DIR/exec-phase.log"
            jlog "exec_done" "out=$REPORT_DIR/exploit"
        fi
    fi
fi

# =============================================================================
# PHASE 6: Aggregate
# =============================================================================
log "Phase 6 — aggregate"

python3 - <<PY > "$REPORT_DIR/summary.json"
import json, pathlib, collections
rd = pathlib.Path("$REPORT_DIR")
findings = []
for f in sorted((rd / "findings").glob("*.json")):
    try:
        d = json.loads(f.read_text())
    except Exception:
        continue
    for fnd in (d.get("findings") or []):
        fnd["_source_file"] = str(f.name)
        findings.append(fnd)

validated = []
for f in sorted((rd / "validated").glob("*.json")):
    try:
        d = json.loads(f.read_text())
    except Exception:
        continue
    for v in (d.get("validated") or []):
        v["_source_file"] = str(f.name)
        validated.append(v)

# v3: pull exec-phase summary if present
exec_summary = None
exec_path = rd / "exploit" / "summary.json"
if exec_path.exists():
    try:
        exec_summary = json.loads(exec_path.read_text())
    except Exception:
        exec_summary = {"_parse_error": True}

sev_counts = collections.Counter(f.get("severity", "UNKNOWN") for f in findings)
verdict_counts = collections.Counter(v.get("verdict", "UNKNOWN") for v in validated)

out = {
    "scan_id": "$SCAN_ID",
    "target": "$TARGET_DIR",
    "language": "$LANG_TAG",
    "model": "$MODEL",
    "pass_at_k": int("$PASS_AT_K"),
    "hunter_findings": len(findings),
    "validated_entries": len(validated),
    "severity_breakdown": dict(sev_counts),
    "validator_verdicts": dict(verdict_counts),
    "exec_phase": exec_summary,   # v3: live-exec verdicts (confirmed PoCs)
    "findings": findings,
    "validated": validated,
}
print(json.dumps(out, indent=2))
PY

echo ""
echo "=========================================================="
echo "  SCAN COMPLETE"
echo "  summary : $REPORT_DIR/summary.json"
echo "  logs    : $LOG_DIR/"
echo "=========================================================="

jlog "scan_done" "report=$REPORT_DIR"
