#!/bin/bash
# =============================================================================
# combine-with-tools.sh — Hybrid: Traditional Tools + Claude Intelligence
# Combines semgrep/codeql/cppcheck output with LLM analysis
# =============================================================================

set -euo pipefail

TARGET_DIR="${1:?Usage: combine-with-tools.sh <target-directory>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORTS_DIR="$(dirname "$SCRIPT_DIR")/reports/hybrid_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$REPORTS_DIR"

echo "Hybrid Analysis: Traditional Tools + Claude"
echo "Target: $TARGET_DIR"
echo ""

# =============================================================================
# Step 1: Run available static analysis tools
# =============================================================================
echo "=== Step 1: Static Analysis ==="

STATIC_RESULTS="$REPORTS_DIR/static_analysis.txt"
> "$STATIC_RESULTS"

# Semgrep (if available)
if command -v semgrep &> /dev/null; then
    echo "Running semgrep..."
    semgrep --config=auto "$TARGET_DIR" --json 2>/dev/null \
        > "$REPORTS_DIR/semgrep.json" || true
    echo "  semgrep: $(jq '.results | length' "$REPORTS_DIR/semgrep.json" 2>/dev/null || echo 0) findings"
    cat "$REPORTS_DIR/semgrep.json" >> "$STATIC_RESULTS"
else
    echo "  semgrep: not installed (pip install semgrep)"
fi

# cppcheck (if available, for C/C++)
if command -v cppcheck &> /dev/null; then
    echo "Running cppcheck..."
    cppcheck --enable=all --xml "$TARGET_DIR" 2> "$REPORTS_DIR/cppcheck.xml" || true
    echo "  cppcheck: done"
    cat "$REPORTS_DIR/cppcheck.xml" >> "$STATIC_RESULTS"
else
    echo "  cppcheck: not installed (apt install cppcheck)"
fi

# flawfinder (if available, for C/C++)
if command -v flawfinder &> /dev/null; then
    echo "Running flawfinder..."
    flawfinder --json "$TARGET_DIR" > "$REPORTS_DIR/flawfinder.json" 2>/dev/null || true
    echo "  flawfinder: done"
    cat "$REPORTS_DIR/flawfinder.json" >> "$STATIC_RESULTS"
else
    echo "  flawfinder: not installed (pip install flawfinder)"
fi

# Bandit (if available, for Python)
if command -v bandit &> /dev/null; then
    echo "Running bandit..."
    bandit -r "$TARGET_DIR" -f json 2>/dev/null \
        > "$REPORTS_DIR/bandit.json" || true
    echo "  bandit: done"
    cat "$REPORTS_DIR/bandit.json" >> "$STATIC_RESULTS"
else
    echo "  bandit: not installed (pip install bandit)"
fi

echo ""

# =============================================================================
# Step 2: Claude triages static analysis output
# =============================================================================
echo "=== Step 2: Claude Triage of Static Analysis ==="

if [ -s "$STATIC_RESULTS" ]; then
    # Truncate if too large
    STATIC_CONTENT=$(head -c 50000 "$STATIC_RESULTS")

    claude -p --output-format json --max-turns 5 --max-budget-usd 2.00 \
        "You are a senior vulnerability researcher. I ran static analysis tools
on a codebase. Here are the raw results:

--- STATIC ANALYSIS OUTPUT ---
$STATIC_CONTENT
--- END OUTPUT ---

Your tasks:
1. Filter out FALSE POSITIVES (common with static analysis)
2. Identify which findings are ACTUALLY EXPLOITABLE
3. For exploitable findings, describe the concrete exploit path
4. Rank the remaining findings by actual risk (not just tool severity)
5. Identify patterns the tools might have MISSED

Output JSON: {
  \"confirmed\": [{severity, file, line, description, exploit_path}],
  \"likely_false_positive\": [{file, line, reason}],
  \"tool_blind_spots\": [\"areas the tools likely missed\"]
}" \
        > "$REPORTS_DIR/triage.json" 2>/dev/null || true

    echo "  Triage complete: $REPORTS_DIR/triage.json"
else
    echo "  No static analysis output to triage"
fi

echo ""

# =============================================================================
# Step 3: Claude deep-dives on blind spots
# =============================================================================
echo "=== Step 3: Deep Analysis of Tool Blind Spots ==="

if [ -f "$REPORTS_DIR/triage.json" ]; then
    BLIND_SPOTS=$(jq -r '.tool_blind_spots[]?' "$REPORTS_DIR/triage.json" 2>/dev/null || echo "")

    if [ -n "$BLIND_SPOTS" ]; then
        claude -p --output-format json --max-turns 10 --max-budget-usd 3.00 \
            "Static analysis tools were run on $TARGET_DIR but likely missed these areas:

$BLIND_SPOTS

Please analyze the codebase focusing SPECIFICALLY on these blind spots.
Use VSP reasoning: trace external inputs through data flow to consumption points.
Look for logic bugs, race conditions, and semantic vulnerabilities that pattern-matching tools miss.

Output any findings as JSON array." \
            > "$REPORTS_DIR/deep_analysis.json" 2>/dev/null || true
        echo "  Deep analysis complete"
    else
        echo "  No blind spots identified"
    fi
fi

echo ""
echo "=== Hybrid Analysis Complete ==="
echo "Results: $REPORTS_DIR/"
echo "  static analysis → semgrep.json, cppcheck.xml, etc."
echo "  triage          → triage.json"
echo "  deep analysis   → deep_analysis.json"
