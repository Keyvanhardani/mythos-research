#!/bin/bash
# =============================================================================
# pass-at-k.sh — Brute-force multiple independent analysis runs on one file
# Usage: pass-at-k.sh <target-file> [k=20] [max-budget-per-run=1.00]
# =============================================================================

set -euo pipefail

TARGET_FILE="${1:?Usage: pass-at-k.sh <target-file> [k] [max-budget]}"
K="${2:-20}"
MAX_BUDGET="${3:-1.00}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPTS_DIR="$(dirname "$SCRIPT_DIR")/prompts"
OUTPUT_DIR="/tmp/pass-at-k-$(date +%s)"

mkdir -p "$OUTPUT_DIR"

echo "Pass@k Analysis: k=$K on $(basename "$TARGET_FILE")"
echo "Budget: \$$MAX_BUDGET per run, \$$(echo "$K * $MAX_BUDGET" | bc) total max"
echo "Output: $OUTPUT_DIR/"
echo ""

VSP_PROMPT=$(cat "$PROMPTS_DIR/vsp-analysis.md")
FILE_CONTENT=$(head -3000 "$TARGET_FILE")
PIDS=()

for i in $(seq 1 "$K"); do
    (
        claude -p --output-format json \
            --max-turns 6 --max-budget-usd "$MAX_BUDGET" \
            "$VSP_PROMPT

This is attempt $i of $K. Take a DIFFERENT analytical angle than obvious approaches.
Try creative attack vectors: integer wrapping, off-by-one, TOCTOU, type confusion.

--- FILE: $TARGET_FILE ---
$FILE_CONTENT
--- END FILE ---

Output findings as JSON. If nothing found, output {\"findings\": [], \"pass\": $i}." \
            > "$OUTPUT_DIR/pass_${i}.json" 2>/dev/null
        echo "  [pass $i] done"
    ) &
    PIDS+=($!)
done

echo "Launched $K parallel passes..."

for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

echo ""
echo "=== Results ==="

# Count findings
TOTAL_FINDINGS=$(grep -rl "vulnerability\|CRITICAL\|HIGH\|MEDIUM\|CWE\|cwe" "$OUTPUT_DIR"/*.json 2>/dev/null | wc -l || echo 0)
echo "Passes with findings: $TOTAL_FINDINGS / $K"

# Aggregate unique findings
echo ""
echo "=== Unique Findings ==="
jq -s '[.[] | .findings[]? // empty] | unique_by(.description // .cwe // .line) | .[] | {severity, cwe, line, description}' "$OUTPUT_DIR"/pass_*.json 2>/dev/null || echo "(no structured findings to aggregate)"

echo ""
echo "Raw results: $OUTPUT_DIR/"
