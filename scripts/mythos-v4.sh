#!/bin/bash
# =============================================================================
# mythos-v4.sh — Live-build agentic orchestrator with self-challenge + FP memory
#
# New in v4 over v3.1 (2026-05-01):
#   - Phase 2.5 [NEW]: build sandbox set-up via lib/build-sandbox.sh — target
#     compiled in scratch, ASan if C/C++. Hunters get Bash+Write+Edit there.
#   - Phase 3 [CHANGED]: hunters now have Bash + Write + Edit tools (Opus's
#     interleaved-thinking is implicit, no explicit Think-tool needed).
#     New prompt prompts/hunter-agent-live.md teaches them to test hypotheses
#     against the live binary (Mythos-style autonomous exploration).
#   - Phase 3.5 [NEW]: adversarial self-challenge between hunt and validator.
#     prompts/self-challenge.md. Drops findings tagged ADVERSE.
#   - Phase 4 [CHANGED]: validator pre-loads cross-session FP memory from
#     dismissals/<target_id>.json so the same FP is not re-flagged twice.
#   - Phase 7 [NEW]: writes back dismissals.json with this run's
#     FALSE_POSITIVE / ADVERSE markings.
#   - --prompt-style {full,minimal} for A/B comparison vs Mythos's
#     "Please find a security vulnerability" minimalism.
#   - --pass-at-k default raised from 1 to 3 (cache-warm runs amortise).
#
# Pipeline:
#   Phase 0   Language detection
#   Phase 1   Sink-guided slicing
#   Phase 2   File ranking (sink density × tier)
#   Phase 2.5 Build sandbox set-up                    [NEW v4]
#   Phase 3   LIVE agentic hunt (Bash+Write+Edit)     [CHANGED v4]
#   Phase 3.5 Adversarial self-challenge              [NEW v4]
#   Phase 4   Skeptical validator (+FP memory)        [CHANGED v4]
#   Phase 5   Live-exec validator for HIGH/CRIT  (existing v3)
#   Phase 6   Aggregate + summary
#   Phase 7   Update dismissals.json                  [NEW v4]
#
# Usage:
#   mythos-v4.sh <target-dir> [--max-files N] [--budget USD] [--language X]
#                             [--pass-at-k K]                 (default 3)
#                             [--prompt-style full|minimal]   (default full)
#                             [--no-build-sandbox]
#                             [--no-self-challenge]
#                             [--no-fp-memory]
#                             [--min-exec-severity HIGH|MEDIUM]
#                             [--skip-exec] [--model MODEL]
#
# Research Edition: Claude backend only. The internal multi-backend
# orchestrator is held private along with the Phase 5 live-exec validator.
# =============================================================================

set -euo pipefail

# --- Defaults ---
TARGET_DIR=""
MAX_FILES=8
BUDGET_PER_RUN="3.00"
LANG_OVERRIDE=""
MODEL="claude-opus-4-7"
PASS_AT_K=3                          # v4: default raised from 1 to 3
PROMPT_STYLE="full"                  # v4: full | minimal
USE_BUILD_SANDBOX=1                  # v4: --no-build-sandbox to disable
USE_SELF_CHALLENGE=1                 # v4: --no-self-challenge to disable
USE_FP_MEMORY=1                      # v4: --no-fp-memory to disable
MIN_EXEC_SEVERITY="HIGH"
SKIP_EXEC=0
EXEC_BUDGET="3.00"
EXEC_MAX_CONCURRENT="2"
EXEC_MAX_TURNS="50"
CHALLENGE_BUDGET="0.75"              # v4: per-finding self-challenge budget
SCAN_ID="mythos4_$(date +%Y%m%d_%H%M%S)_$$"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_DIR="$BASE_DIR/reports/$SCAN_ID"
LOG_DIR="$BASE_DIR/logs/$SCAN_ID"
PROMPTS_DIR="$BASE_DIR/prompts"
LIB_DIR="$BASE_DIR/scripts/lib"
DISMISSALS_DIR="$BASE_DIR/dismissals"

while [[ $# -gt 0 ]]; do
    case $1 in
        --max-files)             MAX_FILES="$2"; shift 2 ;;
        --budget)                BUDGET_PER_RUN="$2"; shift 2 ;;
        --language)              LANG_OVERRIDE="$2"; shift 2 ;;
        --model)                 MODEL="$2"; shift 2 ;;
        --pass-at-k)             PASS_AT_K="$2"; shift 2 ;;
        --prompt-style)          PROMPT_STYLE="$2"; shift 2 ;;
        --no-build-sandbox)      USE_BUILD_SANDBOX=0; shift ;;
        --no-self-challenge)     USE_SELF_CHALLENGE=0; shift ;;
        --no-fp-memory)          USE_FP_MEMORY=0; shift ;;
        --min-exec-severity)     MIN_EXEC_SEVERITY="$2"; shift 2 ;;
        --skip-exec)             SKIP_EXEC=1; shift ;;
        --exec-budget)           EXEC_BUDGET="$2"; shift 2 ;;
        --exec-max-concurrent)   EXEC_MAX_CONCURRENT="$2"; shift 2 ;;
        --exec-max-turns)        EXEC_MAX_TURNS="$2"; shift 2 ;;
        --challenge-budget)      CHALLENGE_BUDGET="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,40p' "$0"; exit 0 ;;
        *)
            if [ -z "$TARGET_DIR" ]; then TARGET_DIR="$1"; else
                echo "unexpected arg: $1" >&2; exit 1
            fi
            shift ;;
    esac
done

if [ -z "$TARGET_DIR" ]; then
    echo "Error: target directory required" >&2
    echo "Usage: mythos-v4.sh <target-dir> [...]" >&2
    exit 1
fi
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

case "$PROMPT_STYLE" in
    full|minimal) ;;
    *) echo "invalid --prompt-style: $PROMPT_STYLE (full|minimal)" >&2; exit 1 ;;
esac

mkdir -p "$REPORT_DIR"/{findings,challenged,validated,slices,sandbox} "$LOG_DIR" "$DISMISSALS_DIR"

# --- Target ID for cross-session FP memory ---
TARGET_ID=$(printf '%s' "$TARGET_DIR" | sha256sum | cut -c1-16)
DISMISSALS_FILE="$DISMISSALS_DIR/${TARGET_ID}.json"

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
echo " mythos-v4  |  scan $SCAN_ID"
echo " target      : $TARGET_DIR"
echo " target_id   : $TARGET_ID"
echo " model       : $MODEL"
echo " budget      : \$$BUDGET_PER_RUN per hunter, max $MAX_FILES files × pass-at-k=$PASS_AT_K"
echo " prompt      : $PROMPT_STYLE"
echo " sandbox     : $([ "$USE_BUILD_SANDBOX" = 1 ] && echo on || echo off)"
echo " self-chal   : $([ "$USE_SELF_CHALLENGE" = 1 ] && echo "on (\$$CHALLENGE_BUDGET each)" || echo off)"
echo " fp memory   : $([ "$USE_FP_MEMORY" = 1 ] && echo "on ($DISMISSALS_FILE)" || echo off)"
echo " report      : $REPORT_DIR"
echo "=========================================================="

jlog "scan_start" "target=$TARGET_DIR target_id=$TARGET_ID prompt=$PROMPT_STYLE pass_at_k=$PASS_AT_K"

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

case "$LANG_TAG" in
    php)     VSP_PROMPT="$PROMPTS_DIR/vsp-php.md" ;;
    python)  VSP_PROMPT="$PROMPTS_DIR/vsp-python.md" ;;
    js-ts|js|ts)
        LANG_TAG="js-ts"; VSP_PROMPT="$PROMPTS_DIR/vsp-js-ts.md" ;;
    c-cpp|c|cpp)
        LANG_TAG="c-cpp"; VSP_PROMPT="$PROMPTS_DIR/vsp-c-cpp.md" ;;
    *)
        echo "No VSP prompt for language '$LANG_TAG' — falling back to generic" >&2
        VSP_PROMPT="$PROMPTS_DIR/vsp-analysis.md"
        ;;
esac

log "  detected: $LANG_TAG  (vsp: $(basename "$VSP_PROMPT"))"
jlog "language" "$LANG_TAG"

# =============================================================================
# PHASE 1: Sink slicing
# =============================================================================
log "Phase 1 — sink slicing"
"$LIB_DIR/sink-slicer.sh" "$TARGET_DIR" "$LANG_TAG" "$REPORT_DIR/slices" 2>&1 \
    | tee -a "$LOG_DIR/slicer.log" >&2

SINK_HITS=$(wc -l < "$REPORT_DIR/slices/sinks.ndjson" | tr -d ' ')
log "  $SINK_HITS sink hits"
jlog "sinks" "hits=$SINK_HITS"

if [ "$SINK_HITS" -eq 0 ]; then
    echo "No sinks found — nothing to hunt. Exit." >&2
    exit 0
fi

# =============================================================================
# PHASE 2: File ranking
# =============================================================================
log "Phase 2 — file ranking"

python3 - <<PY > "$REPORT_DIR/ranked-files.txt"
import json, collections, pathlib, re
slice_path = pathlib.Path("$REPORT_DIR/slices/sinks.ndjson")
cats_per_file = collections.defaultdict(set)

SAFE_PATTERNS = {
    "OBJECT_INJECTION": re.compile(r"allowed_classes", re.I),
    "DESERIALIZE":      re.compile(r"(SafeLoader|allowed_modules|filter\s*=\s*['\"]data['\"])", re.I),
    "CODE_EVAL":        re.compile(r"(ast\.literal_eval|literal_eval|assert\s*\(\s*['\"])", re.I),
    "XXE":              re.compile(r"(libxml_disable_entity_loader|defusedxml|resolve_entities\s*=\s*False)", re.I),
    "SQL_INJECTION":    re.compile(r"(->\s*prepare\s*\(|\?|:[a-zA-Z_])", re.I),
}

TIER_A = {"OBJECT_INJECTION", "DESERIALIZE",
          "CODE_EVAL", "TEMPLATE_INJECT",
          "PROTOTYPE_POLLUTION", "XXE",
          "SQL_INJECTION", "NOSQL_INJECTION",
          "LIVESTATUS_INJECT",
          "DYNAMIC_REQUIRE",
          "SANITIZER_REVIEW",
          "BROWSER_API_FOOTGUN",
          "FRAMEWORK_FOOTGUN"}
TIER_B = {"COMMAND_EXEC", "DYNAMIC_INCLUDE", "SSRF",
          "CALLBACK_INJECTION", "VAR_INJECTION",
          "ZIP_SLIP", "PATH_TRAVERSAL",
          "HEADER_INJECTION", "XSS_RAW", "XSS",
          "REDOS", "OPEN_REDIRECT",
          "WEAK_JWT", "WEAK_CRYPTO",
          "FORMAT_STRING", "ALLOC_COMPUTED",
          "MEMORY_UNCHECKED"}

count_a = collections.Counter()
count_b = collections.Counter()
count_c = collections.Counter()

for line in slice_path.read_text().splitlines():
    if not line.strip(): continue
    ev = json.loads(line)
    f, c, snip = ev["file"], ev["category"], ev.get("snippet", "")
    safe_re = SAFE_PATTERNS.get(c)
    if safe_re and safe_re.search(snip):
        count_c[f] += 1; continue
    cats_per_file[f].add(c)
    if c in TIER_A:   count_a[f] += 1
    elif c in TIER_B: count_b[f] += 1
    else:             count_c[f] += 1

def _is_likely_vendor(path):
    import re, pathlib as _pl
    p = path.replace(chr(92), "/").lower() if "/" not in path else path.lower()
    if re.search(r"/(public|static|assets)/.*\.(js|ts)$", p):
        if count_a[path] + count_b[path] >= 30: return True
    for tok in ("ext-all", "jquery", "bootstrap", "codemirror", "lodash",
                "moment", "angular", ".min.", "-bundle", ".bundle.", ".pack."):
        if tok in p: return True
    try:
        if _pl.Path(path).exists() and _pl.Path(path).stat().st_size > 500_000:
            return True
    except Exception: pass
    return False

def key(f):
    distinct_a = len(cats_per_file[f] & TIER_A)
    vendor_penalty = 1 if _is_likely_vendor(f) else 0
    return (vendor_penalty, -distinct_a, -count_a[f],
            -len(cats_per_file[f] & TIER_B), -count_b[f], -count_c[f], f)

ordered = sorted(cats_per_file, key=key)
for path in ordered[: $MAX_FILES * 4]:
    a = sorted(cats_per_file[path] & TIER_A)
    b = sorted(cats_per_file[path] & TIER_B)
    all_cats = ",".join(sorted(cats_per_file[path]))
    tier = "A" if a else ("B" if b else "C")
    total = count_a[path] + count_b[path] + count_c[path]
    print(f"{tier}\t{total}\t{path}\t{all_cats}")
PY

TOP_FILES=$(head -"$MAX_FILES" "$REPORT_DIR/ranked-files.txt" | cut -f3)
SELECTED=$(printf '%s\n' "$TOP_FILES" | grep -c . || echo 0)
log "  selected $SELECTED files"
jlog "ranking_done" "selected=$SELECTED"

if [ "$SELECTED" -eq 0 ]; then
    echo "No files ranked — exit." >&2
    exit 0
fi

# =============================================================================
# PHASE 2.5 [v4-NEW]: build sandbox set-up
# =============================================================================
SCRATCH=""
SANDBOX_NOTE="(disabled — running in read-only mode)"
SANDBOX_READY="false"

if [ "$USE_BUILD_SANDBOX" = 1 ]; then
    log "Phase 2.5 — build sandbox set-up"
    SCRATCH="$REPORT_DIR/sandbox/scratch"
    mkdir -p "$SCRATCH"
    SANDBOX_DESC=$("$LIB_DIR/build-sandbox.sh" "$TARGET_DIR" "$SCRATCH" "$LANG_TAG" 2>>"$LOG_DIR/sandbox.log" || echo '{"ready":false,"error":"build-sandbox.sh failed"}')
    echo "$SANDBOX_DESC" > "$REPORT_DIR/sandbox/descriptor.json"
    SANDBOX_READY=$(printf '%s' "$SANDBOX_DESC" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("true" if d.get("ready") else "false")' 2>/dev/null || echo false)
    SANDBOX_NOTE=$(printf '%s' "$SANDBOX_DESC" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("note","")[:200])' 2>/dev/null || echo "")
    log "  sandbox ready=$SANDBOX_READY  note=\"$SANDBOX_NOTE\""
    jlog "sandbox" "ready=$SANDBOX_READY note=$SANDBOX_NOTE"
else
    log "Phase 2.5 — sandbox SKIPPED (--no-build-sandbox)"
    jlog "sandbox_skipped" "reason=--no-build-sandbox"
fi

# =============================================================================
# PHASE 3: Live-build agentic hunt
# =============================================================================
log "Phase 3 — live agentic hunt (parallel, k=$PASS_AT_K)"

if [ "$PROMPT_STYLE" = "minimal" ]; then
    HUNTER_PROMPT_FILE="$PROMPTS_DIR/hunter-agent-minimal.md"
else
    HUNTER_PROMPT_FILE="$PROMPTS_DIR/hunter-agent-live.md"
fi
HUNTER_MISSION=$(cat "$HUNTER_PROMPT_FILE")

VSP_BODY=""
if [ "$PROMPT_STYLE" = "full" ] && [ -f "$VSP_PROMPT" ]; then
    VSP_BODY=$(cat "$VSP_PROMPT")
fi

# --- Cross-session FP memory ----------------------------------------------
DISMISSALS_BLOCK=""
if [ "$USE_FP_MEMORY" = 1 ] && [ -f "$DISMISSALS_FILE" ]; then
    DISMISSALS_BLOCK=$(python3 - "$DISMISSALS_FILE" <<'PY'
import json, sys, pathlib
try:
    d = json.loads(pathlib.Path(sys.argv[1]).read_text())
except Exception:
    print(""); sys.exit(0)
items = []
for run in d.get("runs", []):
    for fp in run.get("dismissed", []):
        items.append(fp)
if not items:
    print(""); sys.exit(0)
print("## Previously dismissed findings on this target\n")
print("These claims have been investigated in prior scans and validated as FALSE_POSITIVE.")
print("Do NOT re-flag the same sink + reason unless you have new concrete evidence.\n")
for fp in items[-50:]:  # cap for prompt size
    sf = fp.get("sink_file","?")
    sl = fp.get("sink_line","?")
    fn = fp.get("sink_function","")
    rs = fp.get("reason","")[:160]
    print(f"- {sf}:{sl} ({fn}) — {rs}")
PY
)
fi

# --- per-file sink slice ---------------------------------------------------
build_slice_for_file() {
    local file="$1"
    python3 - "$REPORT_DIR/slices/sinks.ndjson" "$file" <<'PY'
import json, sys
ndjson, target = sys.argv[1], sys.argv[2]
hits = []
for line in open(ndjson):
    if not line.strip(): continue
    ev = json.loads(line)
    if ev["file"] == target: hits.append(ev)
hits.sort(key=lambda h: h["line"])
for h in hits:
    print(f"  L{h['line']:<5} {h['category']:<22} {h['snippet'].strip()[:120]}")
PY
}

pick_focus_hint() {
    local file="$1" k="$2"
    [ "$k" -le 1 ] && { echo ""; return; }
    python3 - "$REPORT_DIR/slices/sinks.ndjson" "$file" "$k" <<'PY'
import json, sys, collections, re
ndjson, target, k = sys.argv[1], sys.argv[2], int(sys.argv[3])
cats = collections.Counter(); fn_like = collections.Counter()
for line in open(ndjson):
    if not line.strip(): continue
    ev = json.loads(line)
    if ev.get("file") != target: continue
    cats[ev.get("category","?")] += 1
    snip = ev.get("snippet","")
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

# Tools given to the hunter:
#   When sandbox is on:  Read, Grep, Glob, Bash, Edit, Write
#   When sandbox is off: Read, Grep, Glob (read-only, no Bash to be safe)
# Note: Claude Code does not expose a "Think" tool — interleaved thinking is
# automatic on Opus models. Prompts encourage think-then-act phrasing.
hunter_tools_args() {
    if [ "$USE_BUILD_SANDBOX" = 1 ] && [ "$SANDBOX_READY" = "true" ]; then
        echo '--allowed-tools Read Grep Glob Bash Edit Write --disallowed-tools NotebookEdit WebFetch WebSearch'
    else
        echo '--allowed-tools Read Grep Glob --disallowed-tools Bash Edit Write NotebookEdit WebFetch WebSearch'
    fi
}

hunter_dirs_args() {
    local out="--add-dir $TARGET_DIR"
    if [ -n "$SCRATCH" ] && [ "$SANDBOX_READY" = "true" ]; then
        out="$out --add-dir $SCRATCH"
    fi
    echo "$out"
}

hunt_file() {
    local file="$1" run_idx="${2:-1}" focus_hint="${3:-}"
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

${focus_hint}. Explicitly avoid re-analysing areas that a parallel-run hunter would
cover; divergent focus is intentional.
"
    fi

    local sandbox_block=""
    if [ "$USE_BUILD_SANDBOX" = 1 ] && [ "$SANDBOX_READY" = "true" ]; then
        sandbox_block="

## Build sandbox

\`\`\`json
$(cat "$REPORT_DIR/sandbox/descriptor.json")
\`\`\`

You have **read+write+bash** in \`$SCRATCH\`. Build extra files there if useful.
Do NOT modify \`$TARGET_DIR\`. If you want to instrument source, copy a file into
\`$SCRATCH/source/\` first, then edit and rebuild from that copy."
    elif [ "$USE_BUILD_SANDBOX" = 1 ] && [ "$SANDBOX_READY" != "true" ]; then
        sandbox_block="

## Build sandbox

Build sandbox setup did not succeed. You are operating **read-only** on the
target source. Improvise: trace by reading code, do not attempt to run."
    fi

    local prompt
    prompt=$(cat <<PROMPT
$HUNTER_MISSION
${VSP_BODY:+

---

## Language-specific taxonomy

$VSP_BODY
}
${DISMISSALS_BLOCK:+

---

$DISMISSALS_BLOCK
}

---

## Target for this run

**Project root (cwd):** \`$TARGET_DIR\`
**Primary file under investigation:** \`$rel\`
$focus_block
## Pre-computed sinks in this file

$slice
$sandbox_block

These are grep hits. They are **candidates**, not confirmed bugs. Pick the most promising,
trace input sources backwards, then issue a final strict-JSON verdict per the format spec above.
PROMPT
)

    local tools_args dirs_args
    tools_args=$(hunter_tools_args)
    dirs_args=$(hunter_dirs_args)

    (
        cd "$TARGET_DIR"
        # shellcheck disable=SC2086
        printf '%s' "$prompt" | claude -p \
            --model "$MODEL" \
            --output-format stream-json \
            --include-partial-messages \
            --verbose \
            --input-format text \
            $tools_args \
            $dirs_args \
            --permission-mode bypassPermissions \
            --max-turns 60 \
            --max-budget-usd "$BUDGET_PER_RUN" \
            > "$log_file" 2>&1
    ) || true

    extract_finding_json "$log_file" "$out"
    jlog "hunt_done" "file=$rel k=$run_idx"
    printf '  ✓ %s%s\n' "$rel" "$([ "$run_idx" -gt 1 ] && echo " (k=$run_idx)" || true)"
}

# Shared verdict-extraction helper (used by hunt + challenge + validate)
extract_finding_json() {
    local log_path="$1" out_path="$2"
    python3 - "$log_path" "$out_path" <<'PY' || true
import json, re, sys, pathlib
log_path, out_path = sys.argv[1], sys.argv[2]
final_text = ""
raw = pathlib.Path(log_path).read_text(errors="replace").strip()
# Direct-JSON path (single-object responses)
try:
    direct = json.loads(raw)
    if isinstance(direct, dict) and ("findings" in direct or "verdict" in direct):
        final_text = raw
except Exception: pass
# Stream-JSON walk
if not final_text:
    for line in raw.splitlines():
        line = line.strip()
        if not line or not line.startswith("{"): continue
        try: ev = json.loads(line)
        except Exception: continue
        if ev.get("type") == "result":
            final_text = ev.get("result", "") or ""; break
        if ev.get("type") == "assistant" and "message" in ev:
            for block in ev["message"].get("content", []):
                if block.get("type") == "text":
                    final_text = block.get("text", "") or final_text

def extract(text):
    if not text: return None
    for m in re.finditer(r"```(?:json)?\s*\n(.*?)\n```", text, flags=re.S):
        blob = m.group(1).strip()
        if blob.startswith("{"):
            try: return json.loads(blob)
            except Exception: pass
    depth = 0; end = None
    for i in range(len(text) - 1, -1, -1):
        c = text[i]
        if c == "}":
            if depth == 0: end = i + 1
            depth += 1
        elif c == "{":
            depth -= 1
            if depth == 0 and end is not None:
                cand = text[i:end]
                try: return json.loads(cand)
                except Exception: end = None; depth = 0; continue
    start = text.rfind("{")
    while start != -1:
        try: return json.loads(text[start:])
        except Exception: start = text.rfind("{", 0, start)
    return None

result = extract(final_text)
with open(out_path, "w") as f:
    if result is not None:
        json.dump(result, f, indent=2)
    else:
        json.dump({"error": "no_parseable_json", "raw_tail": final_text[-2000:]}, f, indent=2)
PY
}

PIDS=()
INDEX=0
TOTAL_RUNS=$((SELECTED * PASS_AT_K))
while IFS= read -r file; do
    [ -z "$file" ] && continue
    INDEX=$((INDEX + 1))
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
# PHASE 3.5 [v4-NEW]: adversarial self-challenge
# =============================================================================
if [ "$USE_SELF_CHALLENGE" = 1 ]; then
    log "Phase 3.5 — adversarial self-challenge"
    CHALLENGE_PROMPT=$(cat "$PROMPTS_DIR/self-challenge.md")

    challenge_finding() {
        local f="$1"
        local slug=$(basename "$f" .json)
        local out="$REPORT_DIR/challenged/${slug}.json"
        local log_file="$LOG_DIR/challenge_${slug}.log"

        if ! grep -q '"findings"' "$f" 2>/dev/null; then return 0; fi
        if grep -q '"verdict"\s*:\s*"CLEAN"' "$f" 2>/dev/null; then return 0; fi

        local finding_content
        finding_content=$(cat "$f")

        local prompt
        prompt=$(cat <<PROMPT
$CHALLENGE_PROMPT

You have Read/Grep/Glob tool access to the source tree under \`$TARGET_DIR\`.
Verify every claim against the live code.

--- FINDING TO CHALLENGE ---
$finding_content
--- END FINDING ---

Output strict JSON per the schema in your brief, single message.
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
                --max-turns 25 \
                --max-budget-usd "$CHALLENGE_BUDGET" \
                > "$log_file" 2>&1
        ) || true

        extract_finding_json "$log_file" "$out"
        jlog "challenge_done" "file=$slug"
        printf '  ⚔ challenged %s\n' "$slug"
    }

    CPIDS=()
    for f in "$REPORT_DIR"/findings/*.json; do
        [ -f "$f" ] || continue
        challenge_finding "$f" &
        CPIDS+=($!)
    done
    for pid in "${CPIDS[@]}"; do wait "$pid" || true; done
else
    log "Phase 3.5 — self-challenge SKIPPED (--no-self-challenge)"
    jlog "challenge_skipped" "reason=--no-self-challenge"
fi

# =============================================================================
# PHASE 4: Validation (with FP memory)
# =============================================================================
log "Phase 4 — validation"
VALIDATION_PROMPT=$(cat "$PROMPTS_DIR/validation.md")

validate_finding() {
    local f="$1"
    local slug=$(basename "$f" .json)
    local out="$REPORT_DIR/validated/${slug}.json"
    local log_file="$LOG_DIR/val_${slug}.log"

    if ! grep -q '"findings"' "$f" 2>/dev/null; then return 0; fi
    if grep -q '"verdict"\s*:\s*"CLEAN"' "$f" 2>/dev/null; then return 0; fi

    # Skip findings the self-challenge ruled ADVERSE
    local challenge_file="$REPORT_DIR/challenged/${slug}.json"
    if [ -f "$challenge_file" ] && grep -q '"verdict"\s*:\s*"ADVERSE"' "$challenge_file" 2>/dev/null; then
        python3 - "$challenge_file" "$out" <<'PY' || true
import json, sys
ch = json.load(open(sys.argv[1]))
json.dump({"validated":[{"original_finding":"dropped by self-challenge",
            "verdict":"FALSE_POSITIVE","adjusted_severity":"NONE",
            "reasoning":ch.get("verdict_reason",""),
            "missed_mitigations":ch.get("missed_mitigations",[]),
            "exploitability_notes":"Phase 3.5 self-challenge marked ADVERSE — finding dropped before validator."}]},
            open(sys.argv[2],"w"), indent=2)
PY
        printf '  ⊘ skipped (ADVERSE self-challenge): %s\n' "$slug"
        return 0
    fi

    local finding_content
    finding_content=$(cat "$f")

    local challenge_block=""
    if [ -f "$challenge_file" ]; then
        challenge_block="

## Self-challenge result (Phase 3.5)

\`\`\`json
$(cat "$challenge_file")
\`\`\`

Take this into account but do your own independent verification."
    fi

    local prompt
    prompt=$(cat <<PROMPT
$VALIDATION_PROMPT
${DISMISSALS_BLOCK:+

---

$DISMISSALS_BLOCK
}

You have Read/Grep/Glob tool access to the actual source tree under \`$TARGET_DIR\`.
**Verify every file:line claim against the live code.** If a cited line does not contain
what the report says, mark it FALSE_POSITIVE.

--- HUNTER REPORT TO VERIFY ---
$finding_content
--- END REPORT ---
$challenge_block

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

    extract_finding_json "$log_file" "$out"
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
# PHASE 5: live-exec validator (existing v3)
# =============================================================================
if [ "$SKIP_EXEC" = "1" ]; then
    log "Phase 5 — SKIPPED (--skip-exec)"
    jlog "exec_skipped" "reason=--skip-exec"
else
    log "Phase 5 — live-exec validation (min-severity=$MIN_EXEC_SEVERITY)"
    jlog "exec_start" "min_severity=$MIN_EXEC_SEVERITY"
    EXEC_SCRIPT="$BASE_DIR/scripts/exec-validator.sh"
    MYTHOS_EXPLOIT="$BASE_DIR/scripts/mythos-exploit.sh"
    if [ ! -x "$EXEC_SCRIPT" ] || [ ! -x "$MYTHOS_EXPLOIT" ]; then
        log "  WARN: exec-validator/mythos-exploit missing; skipping phase 5"
        jlog "exec_skipped" "reason=tools_missing"
    else
        bash "$MYTHOS_EXPLOIT" "$REPORT_DIR" "$TARGET_DIR" \
            --min-severity "$MIN_EXEC_SEVERITY" \
            --budget "$EXEC_BUDGET" \
            --max-concurrent "$EXEC_MAX_CONCURRENT" \
            --max-turns "$EXEC_MAX_TURNS" 2>&1 | tee -a "$LOG_DIR/exec-phase.log"
        jlog "exec_done" "out=$REPORT_DIR/exploit"
    fi
fi

# =============================================================================
# PHASE 6: aggregate
# =============================================================================
log "Phase 6 — aggregate"

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

challenged = []
for f in sorted((rd / "challenged").glob("*.json")):
    try: d = json.loads(f.read_text())
    except Exception: continue
    d["_source_file"] = f.name
    challenged.append(d)

validated = []
for f in sorted((rd / "validated").glob("*.json")):
    try: d = json.loads(f.read_text())
    except Exception: continue
    for v in (d.get("validated") or []):
        v["_source_file"] = f.name
        validated.append(v)

exec_summary = None
exec_path = rd / "exploit" / "summary.json"
if exec_path.exists():
    try: exec_summary = json.loads(exec_path.read_text())
    except Exception: exec_summary = {"_parse_error": True}

sev_counts = collections.Counter(f.get("severity", "UNKNOWN") for f in findings)
chal_counts = collections.Counter(c.get("verdict", "UNKNOWN") for c in challenged)
verdict_counts = collections.Counter(v.get("verdict", "UNKNOWN") for v in validated)

out = {
    "scan_id":            "$SCAN_ID",
    "target":             "$TARGET_DIR",
    "target_id":          "$TARGET_ID",
    "language":           "$LANG_TAG",
    "model":              "$MODEL",
    "prompt_style":       "$PROMPT_STYLE",
    "pass_at_k":          int("$PASS_AT_K"),
    "build_sandbox_used": "$USE_BUILD_SANDBOX" == "1",
    "self_challenge_used":"$USE_SELF_CHALLENGE" == "1",
    "fp_memory_used":     "$USE_FP_MEMORY" == "1",
    "hunter_findings":    len(findings),
    "challenged_entries": len(challenged),
    "validated_entries":  len(validated),
    "severity_breakdown": dict(sev_counts),
    "challenge_verdicts": dict(chal_counts),
    "validator_verdicts": dict(verdict_counts),
    "exec_phase":         exec_summary,
    "findings":           findings,
    "challenged":         challenged,
    "validated":          validated,
}
print(json.dumps(out, indent=2))
PY

# =============================================================================
# PHASE 7 [v4-NEW]: update dismissals.json with this run's FALSE_POSITIVES
# =============================================================================
if [ "$USE_FP_MEMORY" = 1 ]; then
    log "Phase 7 — update FP memory"
    python3 - "$DISMISSALS_FILE" "$REPORT_DIR" "$SCAN_ID" "$TARGET_DIR" "$TARGET_ID" <<'PY' || true
import json, pathlib, sys, hashlib, datetime
dismissals_path, report_dir, scan_id, target, target_id = sys.argv[1:]
dp = pathlib.Path(dismissals_path)
rd = pathlib.Path(report_dir)

if dp.exists():
    try: store = json.loads(dp.read_text())
    except Exception: store = {}
else:
    store = {}
store.setdefault("target", target)
store.setdefault("target_id", target_id)
store.setdefault("runs", [])

new_dismissed = []

# 1) findings dropped by self-challenge ADVERSE
for f in sorted((rd / "challenged").glob("*.json")):
    try: ch = json.loads(f.read_text())
    except Exception: continue
    if ch.get("verdict") != "ADVERSE": continue
    src_finding_path = rd / "findings" / f.name
    if not src_finding_path.exists(): continue
    try: src = json.loads(src_finding_path.read_text())
    except Exception: continue
    for fnd in (src.get("findings") or []):
        new_dismissed.append({
            "sink_file":     fnd.get("sink_file",""),
            "sink_line":     fnd.get("sink_line",""),
            "sink_function": fnd.get("sink_function",""),
            "reason":        f"adverse self-challenge: {ch.get('verdict_reason','')[:200]}",
            "source":        "phase3.5",
            "hash":          hashlib.sha256(json.dumps({k:fnd.get(k,'') for k in ('sink_file','sink_line','sink_function','exploit_path')}, sort_keys=True).encode()).hexdigest()[:16],
        })

# 2) findings the validator marked FALSE_POSITIVE
for f in sorted((rd / "validated").glob("*.json")):
    try: d = json.loads(f.read_text())
    except Exception: continue
    src_finding_path = rd / "findings" / f.name
    src_findings = []
    if src_finding_path.exists():
        try:
            src = json.loads(src_finding_path.read_text())
            src_findings = src.get("findings") or []
        except Exception: pass
    for v in (d.get("validated") or []):
        if v.get("verdict") not in ("FALSE_POSITIVE","DOWNGRADED"): continue
        # try to map to the source finding
        sf, sl, fn = "", "", ""
        if src_findings:
            sf = src_findings[0].get("sink_file","")
            sl = src_findings[0].get("sink_line","")
            fn = src_findings[0].get("sink_function","")
        new_dismissed.append({
            "sink_file":     sf,
            "sink_line":     sl,
            "sink_function": fn,
            "reason":        f"validator {v.get('verdict','')}: {v.get('reasoning','')[:200]}",
            "source":        "phase4",
            "hash":          hashlib.sha256(json.dumps({"sf":sf,"sl":sl,"fn":fn,"r":v.get('reasoning','')[:120]}, sort_keys=True).encode()).hexdigest()[:16],
        })

if new_dismissed:
    # de-dup against existing entries by hash
    existing = set()
    for r in store.get("runs", []):
        for d in r.get("dismissed", []):
            if "hash" in d: existing.add(d["hash"])
    fresh = [d for d in new_dismissed if d.get("hash") not in existing]
    if fresh:
        store["runs"].append({
            "scan_id":  scan_id,
            "ts":       datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "dismissed": fresh,
        })
        # cap retention: keep last 20 runs
        store["runs"] = store["runs"][-20:]
        dp.write_text(json.dumps(store, indent=2, ensure_ascii=False))
        print(f"appended {len(fresh)} dismissals -> {dp}")
    else:
        print("no new dismissals (all already in store)")
else:
    print("no FALSE_POSITIVE / ADVERSE in this run")
PY
    jlog "fp_memory_updated" "$DISMISSALS_FILE"
else
    log "Phase 7 — FP memory SKIPPED (--no-fp-memory)"
fi

echo ""
echo "=========================================================="
echo "  SCAN COMPLETE"
echo "  summary    : $REPORT_DIR/summary.json"
echo "  logs       : $LOG_DIR/"
echo "  dismissals : $DISMISSALS_FILE"
echo "=========================================================="
