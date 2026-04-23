# Changelog

All notable changes to the Mythos research scaffold. The version history below documents the
evolution of the scaffolding design, not strict semver — Mythos is a research artefact.

## v3.1 — April 2026 (current, open-sourced as Research Edition)

First public release.

**New in v3 over v2:**

- **Diversity seeding** (`--pass-at-k K`). K independent hunters per file, each with a different
  focus hint (sink categories, entry-point heuristics, input markers). Approximates Anthropic's
  1000-run sampling strategy at small scale.
- **Per-phase cost telemetry**. `summary.json` now reports USD spent per phase, total per run.
- **Phase 5 hook** — live-exec validation. The hook is present but the implementation
  (`exec-validator.sh`) is intentionally not shipped in the Research Edition; Phase 5 auto-skips
  with a clear notice.
- **Language-specific vulnerability-semantics prompts** (`prompts/vsp-<lang>.md`) injected into the
  hunter per run based on Phase 0 detection.

## v2 — early 2026 (archived in `scripts/archive/`)

**New in v2 over v1:**

- **Sink-guided slicing** (`lib/sink-slicer.sh`). ripgrep-based catalogue per language, produces an
  NDJSON of call-site hits rather than scanning whole files blind.
- **File ranking** by sink-category density. Demotes files whose hits are all in SAFE patterns.
- **Skeptical validator phase**. A second, more suspicious pass re-reads each finding against the
  source. Drastically reduces false positives vs. v1.
- **Standalone `pass-at-k.sh`** driver. Folded into v3's `--pass-at-k` flag.

## v1 — late 2025 / early 2026 (archived in `scripts/archive/`)

**Initial proof of concept.**

- Single `mythos-scan.sh` orchestrator.
- No sink-slicer, no ranker — hunters were pointed at whole directories.
- No validator phase. Hunters' verdicts went straight to the report.
- Useful as a minimum-viable baseline and as a reference for what the scaffolding actually buys you
  empirically; left in `scripts/archive/` for pedagogical reference.

## Design direction beyond v3

- Extended sink catalogues (GLib, GObject, json-glib for C; framework-specific for PHP and TS).
- Ranker aware of *attack surface value*, not just sink density (de-prioritise benchmark/test fixtures).
- Docker-isolated hunters by default (`--docker IMAGE`).
- Tighter coupling between Phase-3 findings and Phase-4 validation prompts for faster rejection of
  boilerplate false positives.
