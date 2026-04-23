#!/bin/bash
# =============================================================================
# file-ranker.sh — Standalone file prioritization
# Usage: file-ranker.sh <target-directory>
# =============================================================================

set -euo pipefail

TARGET_DIR="${1:?Usage: file-ranker.sh <target-directory>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPTS_DIR="$(dirname "$SCRIPT_DIR")/prompts"

RANKING_PROMPT=$(cat "$PROMPTS_DIR/file-ranking.md")

FILE_LIST=$(find "$TARGET_DIR" -type f \( \
    -name "*.c" -o -name "*.h" -o -name "*.cpp" -o -name "*.cc" \
    -o -name "*.py" -o -name "*.js" -o -name "*.ts" \
    -o -name "*.rs" -o -name "*.go" -o -name "*.java" \
    -o -name "*.rb" -o -name "*.php" \
    \) | sort | head -500)

FILE_COUNT=$(echo "$FILE_LIST" | wc -l)
echo "Ranking $FILE_COUNT files in $TARGET_DIR..." >&2

echo "$FILE_LIST" | claude -p --output-format json \
    --max-turns 5 --max-budget-usd 1.00 \
    "$RANKING_PROMPT

Here are the files to rank:
$FILE_LIST

Output as JSON array: [{\"file\": \"path\", \"rank\": N, \"reason\": \"...\"}]
Sort by rank descending. Only include rank 3-5."
