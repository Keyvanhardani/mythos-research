#!/bin/bash
# =============================================================================
# validator.sh — Standalone finding validation (secondary agent)
# Usage: validator.sh <findings-json-file>
# =============================================================================

set -euo pipefail

FINDINGS_FILE="${1:?Usage: validator.sh <findings-json-file>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPTS_DIR="$(dirname "$SCRIPT_DIR")/prompts"

VALIDATION_PROMPT=$(cat "$PROMPTS_DIR/validation.md")
FINDINGS_CONTENT=$(cat "$FINDINGS_FILE")

claude -p --output-format json \
    --max-turns 5 --max-budget-usd 1.00 \
    "$VALIDATION_PROMPT

--- VULNERABILITY REPORT ---
$FINDINGS_CONTENT
--- END REPORT ---

Validate each finding. Output JSON with your verdicts."
