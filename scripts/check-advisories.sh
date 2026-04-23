#!/bin/bash
# check-advisories.sh — re-query the live state of all known 2026 GHSA submissions.
#
# Edit the PAIRS array below to add / remove tracked advisories.

set -euo pipefail

PAIRS=(
  # Add your own GHSA IDs here, one per line, in the format:
  #   "owner/repo|GHSA-xxxx-xxxx-xxxx"
  # Example:
  #   "example-org/example-repo|GHSA-aaaa-bbbb-cccc"
)

printf '%-25s  %-10s  %-9s  %-18s  %-20s  %s\n' \
  GHSA-ID state severity CVE published repo
printf '%-25s  %-10s  %-9s  %-18s  %-20s  %s\n' \
  ---- ---- ---- --- --- ----

for PAIR in "${PAIRS[@]}"; do
  REPO="${PAIR%|*}"; ID="${PAIR#*|}"
  LINE=$(gh api "/repos/$REPO/security-advisories/$ID" \
    --jq '[.ghsa_id, .state, .severity, (.cve_id // "-"), (.published_at // "not-yet")] | @tsv' 2>&1) || continue
  printf '%s\t%s\n' "$LINE" "$REPO"
done | column -t -s $'\t'
