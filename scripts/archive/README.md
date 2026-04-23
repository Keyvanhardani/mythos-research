# Archive — Mythos v1 and v2

Older iterations of the Mythos orchestrator, kept here as a **pedagogical reference** for readers
who want to see how the scaffolding evolved. They are not the recommended entry point.

For actual scans, use `scripts/mythos-v3.sh`. For the prose version of this evolution, see
[`../../CHANGELOG.md`](../../CHANGELOG.md).

## Files

- **`mythos-scan.sh`** — v1, the original simple orchestrator. No sink-slicer, no ranker, no
  skeptical validator. Useful only as a minimum-viable baseline.

- **`mythos-v2.sh`** — v2, adds sink-guided slicing, file ranking, and the skeptical-validator
  phase. Significantly fewer false positives than v1 but without diversity seeding or per-phase
  cost telemetry.

- **`pass-at-k.sh`** — v2-era standalone driver for K independent runs per file. Folded into v3's
  `--pass-at-k K` flag; kept here to show how pass@k was originally wired.

## Why keep them?

Two reasons:

1. **Evolution is pedagogy.** It's easier to understand *why* v3 is structured the way it is when
   you can read v1 and v2 next to it. Research is not just the final artefact.
2. **Replication honesty.** Anthropic's published scaffold went through iteration too, and that
   iteration is documented in their paper. Mythos follows the same convention.

## Will these receive updates?

No. v3 is where ongoing work goes. If you find a bug in v1 or v2, feel free to note it in a PR
comment, but we won't be patching them — the scaffolding has moved on.
