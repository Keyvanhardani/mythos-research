#!/bin/bash
# =============================================================================
# mythos-scan.sh — Main Orchestrator
# Mythos-style vulnerability discovery scaffold using Claude Code CLI
# =============================================================================

set -euo pipefail

# --- Configuration ---
TARGET_DIR="${1:?Usage: mythos-scan.sh <target-directory> [max-files] [passes-per-file]}"
MAX_FILES="${2:-10}"          # Max rank 4-5 files to scan
PASSES_PER_FILE="${3:-3}"     # pass@k per file
MAX_BUDGET_PER_RUN="${4:-2.00}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REPORTS_DIR="$PROJECT_DIR/reports/$(date +%Y%m%d_%H%M%S)"
PROMPTS_DIR="$PROJECT_DIR/prompts"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARNING:${NC} $1"; }
ok() { echo -e "${GREEN}[$(date +%H:%M:%S)] ✓${NC} $1"; }
err() { echo -e "${RED}[$(date +%H:%M:%S)] ✗${NC} $1"; }

# --- Validate ---
if [ ! -d "$TARGET_DIR" ]; then
    err "Target directory not found: $TARGET_DIR"
    exit 1
fi

if ! command -v claude &> /dev/null; then
    err "Claude CLI not found. Install: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

mkdir -p "$REPORTS_DIR"/{rankings,findings,validated}

log "Mythos Vulnerability Discovery Scaffold"
log "Target: $TARGET_DIR"
log "Max files: $MAX_FILES | Passes per file: $PASSES_PER_FILE"
log "Reports: $REPORTS_DIR"
echo ""

# =============================================================================
# PHASE 1: File Ranking
# =============================================================================
log "═══ PHASE 1: File Prioritization ═══"

RANKING_PROMPT=$(cat "$PROMPTS_DIR/file-ranking.md")

# List all source files for context
FILE_LIST=$(find "$TARGET_DIR" -type f \( -name "*.c" -o -name "*.h" -o -name "*.cpp" -o -name "*.cc" -o -name "*.py" -o -name "*.js" -o -name "*.rs" -o -name "*.go" -o -name "*.java" \) | head -500)

echo "$FILE_LIST" | claude -p --output-format json \
    --max-turns 5 --max-budget-usd 1.00 \
    "$RANKING_PROMPT

Here are the files to rank:
$FILE_LIST

Output as JSON array: [{\"file\": \"path\", \"rank\": N, \"reason\": \"...\"}]
Sort by rank descending. Only include rank 3-5." \
    > "$REPORTS_DIR/rankings/file_rankings.json" 2>/dev/null || true

ok "File rankings saved"

# Extract top files
TOP_FILES=$(jq -r '.[].file' "$REPORTS_DIR/rankings/file_rankings.json" 2>/dev/null | head -"$MAX_FILES" || echo "")

if [ -z "$TOP_FILES" ]; then
    warn "JSON parsing failed, falling back to all source files"
    TOP_FILES=$(echo "$FILE_LIST" | head -"$MAX_FILES")
fi

FILE_COUNT=$(echo "$TOP_FILES" | wc -l)
ok "Selected $FILE_COUNT high-priority files for analysis"
echo ""

# =============================================================================
# PHASE 2: Parallel VSP Analysis (pass@k)
# =============================================================================
log "═══ PHASE 2: VSP Vulnerability Analysis (pass@k=$PASSES_PER_FILE) ═══"

VSP_PROMPT=$(cat "$PROMPTS_DIR/vsp-analysis.md")
PIDS=()

scan_file() {
    local file="$1"
    local pass="$2"
    local basename=$(echo "$file" | tr '/' '_')
    local output="$REPORTS_DIR/findings/${basename}_pass${pass}.json"
    local session_id="scan-${basename}-${pass}"

    # Read the actual file content
    local file_content
    if [ -f "$file" ]; then
        file_content=$(head -2000 "$file")
    else
        echo '{"error": "file not found"}' > "$output"
        return
    fi

    claude --session-id "$session_id" -p --output-format json \
        --max-turns 8 --max-budget-usd "$MAX_BUDGET_PER_RUN" \
        "$VSP_PROMPT

--- FILE: $file ---
$file_content
--- END FILE ---

Analyze this file. Output findings as JSON array. If no vulnerabilities found, output {\"findings\": [], \"file\": \"$file\", \"verdict\": \"CLEAN\"}." \
        > "$output" 2>/dev/null || echo '{"error": "scan failed", "file": "'"$file"'"}' > "$output"
}

# Launch parallel scans
TOTAL_SCANS=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    for pass in $(seq 1 "$PASSES_PER_FILE"); do
        scan_file "$file" "$pass" &
        PIDS+=($!)
        TOTAL_SCANS=$((TOTAL_SCANS + 1))
    done
done <<< "$TOP_FILES"

log "Launched $TOTAL_SCANS parallel scans..."

# Wait for all scans with progress
COMPLETED=0
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
    COMPLETED=$((COMPLETED + 1))
    log "Progress: $COMPLETED/$TOTAL_SCANS scans complete"
done

FINDING_COUNT=$(find "$REPORTS_DIR/findings" -name "*.json" -exec grep -l "vulnerability\|CRITICAL\|HIGH\|MEDIUM" {} \; 2>/dev/null | wc -l || echo 0)
ok "Phase 2 complete. $FINDING_COUNT files contain potential findings."
echo ""

# =============================================================================
# PHASE 3: Validation (Secondary Agent)
# =============================================================================
log "═══ PHASE 3: Finding Validation ═══"

VALIDATION_PROMPT=$(cat "$PROMPTS_DIR/validation.md")
VPIDS=()

validate_finding() {
    local finding_file="$1"
    local basename=$(basename "$finding_file")
    local output="$REPORTS_DIR/validated/validated_${basename}"

    local finding_content=$(cat "$finding_file")

    claude -p --output-format json \
        --max-turns 5 --max-budget-usd 1.00 \
        "$VALIDATION_PROMPT

--- VULNERABILITY REPORT ---
$finding_content
--- END REPORT ---

Validate each finding. Output JSON with your verdicts." \
        > "$output" 2>/dev/null || echo '{"error": "validation failed"}' > "$output"
}

# Only validate files that contain findings
for finding in "$REPORTS_DIR/findings"/*.json; do
    [ -f "$finding" ] || continue
    if grep -ql "vulnerability\|CRITICAL\|HIGH\|MEDIUM\|cwe\|CWE" "$finding" 2>/dev/null; then
        validate_finding "$finding" &
        VPIDS+=($!)
    fi
done

if [ ${#VPIDS[@]} -gt 0 ]; then
    log "Validating ${#VPIDS[@]} reports..."
    for pid in "${VPIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    ok "Validation complete"
else
    warn "No findings to validate"
fi
echo ""

# =============================================================================
# PHASE 4: Aggregate & Report
# =============================================================================
log "═══ PHASE 4: Aggregation ═══"

# Create summary
cat > "$REPORTS_DIR/summary.json" << SUMMARY
{
  "scan_metadata": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "target": "$TARGET_DIR",
    "files_ranked": $FILE_COUNT,
    "total_scans": $TOTAL_SCANS,
    "passes_per_file": $PASSES_PER_FILE,
    "max_budget_per_run": "$MAX_BUDGET_PER_RUN"
  },
  "results": {
    "findings_files": $(find "$REPORTS_DIR/findings" -name "*.json" | wc -l),
    "files_with_findings": $FINDING_COUNT,
    "validated_files": $(find "$REPORTS_DIR/validated" -name "*.json" 2>/dev/null | wc -l)
  }
}
SUMMARY

ok "Summary: $REPORTS_DIR/summary.json"

# Print quick stats
echo ""
echo "════════════════════════════════════════"
echo "  SCAN COMPLETE"
echo "════════════════════════════════════════"
echo "  Target:     $TARGET_DIR"
echo "  Files:      $FILE_COUNT ranked, $TOTAL_SCANS total scans"
echo "  Findings:   $FINDING_COUNT files with potential vulnerabilities"
echo "  Reports:    $REPORTS_DIR/"
echo ""
echo "  Next steps:"
echo "    cat $REPORTS_DIR/validated/*.json | jq '.'"
echo "    # Review confirmed findings"
echo "════════════════════════════════════════"
