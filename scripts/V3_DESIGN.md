# Mythos v3 — Design Document

**Status:** in progress (2026-04-20)
**Author:** Keyvan Hardani (with Claude)
**Trigger:** Anthropic's *Claude Mythos Preview* model card + blog, read 2026-04-20.
Replicates their pipeline design locally using regular Claude + CVP approval.

## Why v3

v2 of this scaffold already does (and aligns with Anthropic's *Mythos Preview*):

- File ranking 1–5 (`prompts/file-ranking.md`, `scripts/file-ranker.sh`)
- Parallel per-file hunters (`scripts/mythos-v2.sh`, phase 3)
- Skeptical 2nd-pass validator (`prompts/validation.md`, `scripts/validator.sh`)
- pass@k diversity (`scripts/pass-at-k.sh`)
- Per-language VSP prompts (`prompts/vsp-{c-cpp,js-ts,php,python}.md`)
- Simple top-level hunter prompt (`prompts/hunter-agent.md`)

What v2 **does not** do, and what v3 adds:

| Gap | Source in Anthropic's write-up | v3 artifact |
|-----|--------------------------------|-------------|
| Live execution of the PoC against the installed target | "container [with] project-under-test running […] Address Sanitizer for crash oracle" | `scripts/exec-validator.sh` + `prompts/exec-validator.md` |
| Exploit-primitive-chain stage after discovery | "write exploits so we can submit the highest severity ones" | `scripts/mythos-exploit.sh` (wraps exec-validator) |
| Diversity-seeded parallel hunters (same file, different focus) | OpenBSD: ~1000 runs, each agent picks a file, parallel | `scripts/mythos-v3.sh` adds `--focus-hints` |
| `think` tool exposed to the hunter | "Model was also given a 'think' tool that allows interleaved thinking" | v3 hunter invocation adds tool |
| Cost telemetry per run | Anthropic: $20/run, <$50 for critical | v3 summary.json carries `cost_usd` |

## Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│                            mythos-v3.sh                             │
│                                                                     │
│  Phase 0  language detection          (lib/detect-language.sh)      │
│  Phase 1  sink slicing                (lib/sink-slicer.sh)          │
│  Phase 2  file ranking                (embedded python, tier A/B/C) │
│  Phase 3  parallel hunters  +         (VSP prompt + sink slice +    │
│           diversity focus hints       focus-hint per run)            │
│           + `think` tool exposed                                    │
│  Phase 4  skeptical source validator  (validation.md re-used)       │
│  Phase 5  LIVE-EXEC validator  [NEW]  (exec-validator.sh per HIGH)  │
│  Phase 6  EXPLOIT CHAIN        [NEW]  (mythos-exploit.sh, CONFIRMED)│
│  Phase 7  aggregate + summary         (summary.json with cost,      │
│                                         confirmed vs paper-only)    │
└─────────────────────────────────────────────────────────────────────┘
```

## Shipping order

1. **`prompts/exec-validator.md`** (✅ shipped) — exploit-dev agent prompt, evidence-type
   guide, budget discipline, scratch-dir constraints.
2. **`scripts/exec-validator.sh`** (✅ shipped) — per-run scratch dir, per-language install
   (Python venv / npm / cargo / cc), Claude agent with Bash + Read + Write confined to
   scratch, verdict JSON with `confirmed / evidence_type / poc_path / run_output /
   asan_report / severity_adjustment`. Exit 0 if confirmed.
3. **`scripts/mythos-exploit.sh`** (TODO) — wraps exec-validator as a standalone stage:
   takes a findings dir (from a mythos-v2 run) + target dir, iterates all HIGH findings,
   runs exec-validator on each, writes `exploit/` sibling dir with confirmed PoCs.
4. **`scripts/mythos-v3.sh`** (TODO) — full orchestrator. Copy v2, add phases 5+6, add
   diversity-hint generator and per-call cost capture. Keep v2 untouched as fallback.
5. **`prompts/hunter-agent-v3.md`** (TODO — or patch in-place) — add `<focus-hint>` slot
   and `<think>` usage encouragement. Backwards-compatible with v2 hunter runs.

## exec-validator.sh — key decisions

- **Scratch vs Docker.** MVP uses `mktemp -d` on the host. Docker is a planned `--docker
  IMAGE` flag (not yet wired). Rationale: host install is fast (venv + pip), most of our
  targets are Python/Node, and Claude Code inside a container needs extra plumbing. Docker
  matters for C/C++ with ASan and for isolating filesystem writes.
- **Per-language install.**
  - Python: `python3 -m venv .venv --system-site-packages`, `pip install $TARGET_DIR`
    (editable fallback). Agent gets `$SCRATCH/.venv/bin/python`.
  - Node: `npm init -y && npm install $TARGET_DIR`. Agent gets `node_modules` + direct
    require path.
  - Rust: agent builds with cargo.
  - C/C++: agent builds with `CC='gcc -fsanitize=address -g'`.
  - Generic: source on disk; agent designs its own reproducer.
- **Tools granted to the agent.** Read, Grep, Glob on `$TARGET_DIR` (read-only); Bash,
  Write, Edit on `$SCRATCH` (read-write). Denied: NotebookEdit, WebFetch, WebSearch.
  `--permission-mode bypassPermissions` is fine because `--add-dir` confinement guards
  writes, and Bash is needed to actually run the PoC.
- **Verdict schema.** One JSON object, fenced in ```json```, last message:
  ```json
  {
    "confirmed": true|false,
    "evidence_type": "marker_file | crash | asan_report | stdout_string | exit_code | memory_read | environment_unavailable | ''",
    "poc_path": "<absolute path inside scratch>",
    "run_output": "<first 2000 chars>",
    "asan_report": "<full stderr when memory bug; else ''>",
    "verdict_reason": "<one sentence>",
    "severity_adjustment": "KEEP | DOWNGRADE_TO_LOW | DOWNGRADE_TO_MEDIUM | UPGRADE_TO_HIGH | UPGRADE_TO_CRITICAL",
    "severity_reason": "<one sentence>",
    "_scratch": "<scratch dir path>"
  }
  ```
- **Exit code.** 0 confirmed, 1 not confirmed, 2 parse error / no verdict.
- **Evidence-type guide** lives in the prompt file — each bug class (cmd-inject, SQLi,
  deserialization, path traversal, shell-inject, memory bug, auth bypass, SSRF) has a
  preferred evidence type.

## Diversity seed — how it works

v2 runs one hunter per top file, one run per hunter. Anthropic runs ~1000 runs over a
repository and asks each agent to focus on a different file; agents re-discover the
same bugs much less often.

v3 keeps the one-hunter-per-file for the default path, **but** supports a pass@K mode
(`--pass-at-k N`) that runs the same file N times with different **focus hints**:

```
Hint catalog for file X is derived from:
  - sink categories present in the file (from phase 1 sink slicer output)
  - function names longer than 8 chars found in the file (heuristic entry points)
  - untrusted-input markers: @app.route, socket.on, request.get_json, req.body, …
```

The hint is injected into the hunter prompt as a `## Focus for this run` section.
Identical prompts but differing hints → divergent reasoning paths → diverse findings.

## Anthropic model config

Per model card (section 3.3):
> *All evaluations below are performed with sampling settings: no thinking, default
> effort, temperature, and top_p. The model was also given a "think" tool that allows
> interleaved thinking for multi-turn evaluations.*

For v3, the hunter invocation in `mythos-v3.sh`:

- `--model "claude-opus-4-7"` (or newer; parametrized)
- No extra temperature / thinking flags (inherit CLI defaults)
- Add `--allowed-tools` entry for `mcp__think__think` if available; else we emulate the
  think tool via a prompt-level scratchpad ("Before acting, write your hypothesis in a
  `think:` block"). The prompt-level fallback is good enough.

## Cost telemetry

Each `claude -p` invocation in v3 captures `total_cost_usd` from the final `result` event
in the stream-json log. Aggregate into `summary.json.cost_usd_per_phase` and
`summary.json.cost_usd_total`. Matches Anthropic's "$20/run, <$50 for critical" framing.

## Anthropic's Mythos we cannot replicate

- **The model itself.** `claude-mythos-preview` is Anthropic-only (Project Glasswing
  partners). We run `claude-opus-4-7` or whichever public model is latest. Expect a
  delta on the hardest exploit-dev tasks.
- **The large-scale campaign budget.** OpenBSD 1000-run campaigns cost ~$20k. We run
  small-scale targeted hunts.
- **CyberGym / Cybench benchmark runs at scale.** We don't have the eval harness.

## Prior art in this repo (don't re-invent)

- `scripts/mythos-v2.sh` — current orchestrator.
- `scripts/lib/detect-language.sh` — language detection.
- `scripts/lib/sink-slicer.sh` — grep-based sink hits → `sinks.ndjson`.
- `scripts/lib/hunter-qwen.py` — alternative Qwen backend (not the default path for v3).
- `scripts/pass-at-k.sh` — existing K-independent-runs driver; v3 generalizes this with
  diversity hints rather than pure replay.
- `scripts/validator.sh` — 2nd-pass skeptical validator (Phase 4).


## Open questions

- Should the exec-validator be rate-limited per target (e.g. max 3 concurrent)? For now
  it runs one at a time from `mythos-exploit.sh`.
- Should CONFIRMED findings auto-generate a GHSA-ready `FINDING.md` + email draft? The
  could ship a `scripts/mythos-submit.sh` that consumes a confirmed finding and writes
  `poc/<slug>/{FINDING.md, EMAIL_TO_*.md, ghsa.json}`. Tracking as post-v3 work.


## Usage (v3)

Full scan with live-exec validation:
```
bash scripts/mythos-v3.sh audit/<target> --max-files 10 --budget 3.00 \
    --pass-at-k 2 --min-exec-severity HIGH --exec-budget 3.00
```

v2 behavior (source-review only, skip live exec):
```
bash scripts/mythos-v3.sh audit/<target> --skip-exec
```

Standalone exploit pass over an existing v2 report:
```
bash scripts/mythos-exploit.sh reports/<scan-id> audit/<target> \
    --min-severity HIGH --budget 3.00 --max-concurrent 2
```

Single-finding live-exec:
```
bash scripts/exec-validator.sh <finding.json> <target-dir> \
    --budget 2.50 --max-turns 40 --out /tmp/verdict.json
```
