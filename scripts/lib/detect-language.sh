#!/bin/bash
# =============================================================================
# detect-language.sh — Classify a target directory by dominant languages.
# Usage:  detect-language.sh <target-dir>
# Output (stdout, JSON):
#   { "dominant": "php", "profile": { "php": 1234, "js": 88, ... } }
# Exit 0 on success, 1 if no recognized source found.
# =============================================================================

set -euo pipefail

TARGET="${1:?Usage: detect-language.sh <target-dir>}"
[ -d "$TARGET" ] || { echo "not a directory: $TARGET" >&2; exit 1; }

# Skip common vendored/noise paths.
EXCLUDES=(
    --exclude-dir=node_modules
    --exclude-dir=vendor
    --exclude-dir=.git
    --exclude-dir=3rdparty
    --exclude-dir=third_party
    --exclude-dir=dist
    --exclude-dir=build
    --exclude-dir=.venv
    --exclude-dir=__pycache__
)

count_ext() {
    local ext="$1"
    find "$TARGET" \
        -type d \( -name node_modules -o -name vendor -o -name .git \
                -o -name 3rdparty -o -name third_party -o -name dist \
                -o -name build -o -name .venv -o -name __pycache__ \) -prune \
        -o -type f -name "*.${ext}" -print 2>/dev/null | wc -l
}

PHP=$(count_ext php)
PY=$(count_ext py)
JS=$(count_ext js)
MJS=$(count_ext mjs)
CJS=$(count_ext cjs)
TS=$(count_ext ts)
TSX=$(count_ext tsx)
JSX=$(count_ext jsx)
C=$(count_ext c)
H=$(count_ext h)
CPP=$(count_ext cpp)
CC=$(count_ext cc)
HPP=$(count_ext hpp)
GO=$(count_ext go)
RS=$(count_ext rs)
JAVA=$(count_ext java)
RB=$(count_ext rb)

JS_TOTAL=$((JS + MJS + CJS + JSX))
TS_TOTAL=$((TS + TSX))
CPP_TOTAL=$((C + H + CPP + CC + HPP))

# Pick dominant language bucket.
max=0
dom="unknown"
for pair in "php:$PHP" "python:$PY" "js-ts:$((JS_TOTAL + TS_TOTAL))" "c-cpp:$CPP_TOTAL" "go:$GO" "rust:$RS" "java:$JAVA" "ruby:$RB"; do
    name="${pair%%:*}"
    cnt="${pair##*:}"
    if [ "$cnt" -gt "$max" ]; then
        max="$cnt"
        dom="$name"
    fi
done

cat <<JSON
{
  "target": "$TARGET",
  "dominant": "$dom",
  "profile": {
    "php":    $PHP,
    "python": $PY,
    "js":     $JS_TOTAL,
    "ts":     $TS_TOTAL,
    "c_cpp":  $CPP_TOTAL,
    "go":     $GO,
    "rust":   $RS,
    "java":   $JAVA,
    "ruby":   $RB
  }
}
JSON
