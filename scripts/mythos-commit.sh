#!/bin/bash
# =============================================================================
# mythos-commit.sh — SHA-3 commitment scheme for unpatched-bug accountability.
#
# Mirrors the Anthropic Mythos Preview "we hash unpatched bugs to commit to
# their existence without disclosing details" pattern.
#
# Hashes a finding JSON's stable content with SHA-3-256 and appends the hash
# (plus metadata) to disclosures/commitments.jsonl. The original finding stays
# private; only the hash is public-citable.
#
# Usage:
#   mythos-commit.sh <finding.json> [--target NAME] [--note "free text"]
#
# The hash covers: severity, cwe, sink_file, sink_line, sink_function,
# source_file, source_line, exploit_path, fix_suggestion. Volatile fields
# (confidence, _source_file, run_output) are excluded so re-running the same
# finding produces a stable commitment.
#
# Output: one JSON line appended to <repo>/disclosures/commitments.jsonl
#   {"ts":"<iso>","hash":"<sha3-256-hex>","target":"<name>","severity":"...",
#    "cwe":"CWE-XXX","note":"..."}
# Plus the same line printed on stdout.
# =============================================================================
set -euo pipefail

FINDING="${1:-}"
if [ -z "$FINDING" ]; then
    sed -n '2,20p' "$0"
    exit 2
fi
shift

TARGET=""
NOTE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --note)   NOTE="$2"; shift 2 ;;
        *) echo "unexpected arg: $1" >&2; exit 2 ;;
    esac
done

if [ ! -f "$FINDING" ]; then
    echo "finding not found: $FINDING" >&2; exit 2;
fi

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMMIT_LOG="$BASE_DIR/disclosures/commitments.jsonl"
mkdir -p "$(dirname "$COMMIT_LOG")"

python3 - "$FINDING" "$TARGET" "$NOTE" "$COMMIT_LOG" <<'PY'
import datetime, hashlib, json, os, sys

finding_path, target, note, commit_log = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(finding_path) as f:
    raw = json.load(f)

# Findings JSON may be a single finding or a {"findings":[...]} container.
items = raw.get("findings") if isinstance(raw, dict) and "findings" in raw else [raw]

stable_keys = (
    "severity", "cwe", "sink_file", "sink_line", "sink_function",
    "source_file", "source_line", "exploit_path", "fix_suggestion",
)

iso_now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
out_lines = []

for item in items:
    if not isinstance(item, dict):
        continue
    canonical = {k: item.get(k, "") for k in stable_keys}
    blob = json.dumps(canonical, sort_keys=True, ensure_ascii=False).encode("utf-8")
    h = hashlib.sha3_256(blob).hexdigest()
    rec = {
        "ts":          iso_now,
        "hash":        h,
        "target":      target or os.path.basename(os.path.dirname(os.path.abspath(finding_path))),
        "severity":    item.get("severity", ""),
        "cwe":         item.get("cwe", ""),
        "sink":        f"{item.get('sink_file','')}:{item.get('sink_line','')}",
        "note":        note,
        "commit_form": "sha3-256(stable_keys_json)",
    }
    out_lines.append(json.dumps(rec, ensure_ascii=False))

if not out_lines:
    print("no findings parsed; nothing committed", file=sys.stderr)
    sys.exit(1)

with open(commit_log, "a") as f:
    for line in out_lines:
        f.write(line + "\n")
        print(line)
PY
