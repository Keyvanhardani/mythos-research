# Notes for running Mythos Research Edition with Claude Code

This file helps Claude Code agents (via `claude -p` or interactive) operate Mythos productively.

## Scope reminder

Mythos Research Edition is a read-only vulnerability-discovery scaffold for open-source self-scan and
coordinated disclosure. All live exploitation stages are held outside this repository.

When running hunters:

- Target directories are **read-only**. Do not modify source trees under audit.
- Findings are sorted HIGH/CRITICAL-first. Anything below HIGH is typically defense-in-depth and not
  publishable as a security finding.
- When in doubt about severity, default to underselling and let the validator (Phase 4) decide.

## Useful Claude Code invocations

Standard run against a target:

    bash scripts/mythos-v3.sh path/to/target --max-files 8 --budget 3.00

Dry-run / review only (no live-exec — the Research Edition default):

    bash scripts/mythos-v3.sh path/to/target --skip-exec

Targeted hunt against specific files (e.g. known trust-boundaries):

    bash scripts/mythos-targeted.sh path/to/target path/to/files.txt

## Reporting findings

If the pipeline surfaces a valid HIGH/CRITICAL finding, please follow coordinated-disclosure
practice:

1. Open a private advisory at the upstream project's security contact
2. Do not publish PoC code until the vendor has acknowledged and patched
3. Use the upstream project's preferred disclosure channel (GHSA, NVD, SECURITY.md, etc.)

See `SECURITY.md` for this repository's disclosure policy.
