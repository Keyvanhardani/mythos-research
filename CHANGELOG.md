# Changelog

All notable changes to the Mythos research scaffold. The version history below documents the
evolution of the scaffolding design, not strict semver — Mythos is a research artefact.

## v2.0 — May 2026 (current, ports the v4 scaffold)

Second public release. Ports the v4 scaffold from the internal toolchain, keeping the live-exec
validator and the multi-platform / weaponising stages out of scope. v3.1 stays in the repo as a
fallback for anyone reproducing the original Research Edition report.

**New phases:**

- **Phase 2.5 — Build sandbox** (`scripts/lib/build-sandbox.sh`). Per-scan scratch dir with the
  target compiled (ASan if C/C++, venv + pip if Python, npm install if Node). Gives hunters scoped
  Bash + Edit + Write inside the scratch dir, Read-only on source.
- **Phase 3.5 — Adversarial self-challenge** (`prompts/self-challenge.md`). Each finding is fed
  back to a fresh agent that argues against it; `ADVERSE` findings are dropped before validation.
- **Phase 7 — FP-memory writeback**. Persists `FALSE_POSITIVE` and `ADVERSE` markings into
  `dismissals/<target_id>.json` so future runs against the same target avoid re-discovering them.

**New hunter modes:**

- **`prompts/hunter-agent-live.md`** — live-exploration brief used by Phase 3 in v4. Hunters test
  hypotheses against the live build instead of tracing statically.
- **`prompts/hunter-agent-minimal.md`** — Mythos-Preview-style minimal brief ("please find a
  security vulnerability in this program"). Selectable via `--prompt-style minimal` for A/B
  comparison against the full VSP.

**New companion utilities:**

- **`scripts/mythos-commit.sh`** — SHA-3-256 commitment scheme for unpatched-bug accountability.
- **`prompts/patch-gen.md`** — minimal-correct fix + regression test from a finding.
- **`prompts/disclosure-writeup.md`** — vendor-ready report templates per channel
  (GHSA / HackerOne / CVE / Bugzilla / vendor-email / oss-security).
- **`prompts/mitigation-map.md`** — userspace mitigation enumeration for severity calibration.
- **`prompts/reliability-test.md`** — finding-stability QA loop.

**Slicer + ranker improvements:**

- `lib/sink-slicer.sh` excludes `docs/examples/`, `examples/`, `demos/`, `samples/`, `tutorial/`,
  `.pnp.*`, and `.yarn/` — discovered during a curl-8.20.0 audit where `docs/examples/*.c` captured
  every top-12 ranking slot.
- Bundled-ripgrep fallback path: if the host doesn't have `rg` on `PATH`, the slicer now also
  looks inside the `claude-code` install directory for the vendored binary.

**Defaults:**

- `--pass-at-k` default raised from 1 to 3 (the build-sandbox phase amortises the cache-warm cost
  across the K runs).
- v4 is the default orchestrator (`scripts/mythos-v4.sh`); v3.1 (`scripts/mythos-v3.sh`) is kept
  in place — not archived — for anyone reproducing the original report.

**Held private (intentionally not in this edition):**

- The Phase 5 live-exec validator (`exec-validator.sh`).
- The v5 multi-platform exploit orchestrator and the Kali sandbox layer.
- Platform-specific exploit-development prompts (web / Windows / macOS / mobile / network /
  recon / kernel-level chains and primitives).
- The local non-Claude backend (Qwen function-calling agent).

These remain outside the public repository to keep Mythos Research Edition a *research scaffold*
and not a turn-key exploitation framework.

## v3.1 — April 2026 (first public release)

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
