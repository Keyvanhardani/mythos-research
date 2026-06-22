<h1 align="center">Mythos Research Edition</h1>

<p align="center">
  <a href="https://doi.org/10.5281/zenodo.19727857"><img alt="DOI" src="https://img.shields.io/badge/DOI-10.5281%2Fzenodo.19727857-3a87a8?style=flat-square"/></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-Apache_2.0-blue?style=flat-square"/></a>
  <a href="https://github.com/Keyvanhardani/mythos-research/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/Keyvanhardani/mythos-research?style=flat-square&color=slategray"/></a>
  <a href="dist/Mythos-Research-Edition.pdf"><img alt="Research report (PDF)" src="https://img.shields.io/badge/paper-PDF-7a5442?style=flat-square"/></a>
  <a href="https://orcid.org/0009-0000-6003-8826"><img alt="ORCID" src="https://img.shields.io/badge/ORCID-0009--0000--6003--8826-A6CE39?style=flat-square&logo=orcid&logoColor=white"/></a>
  <img alt="Research Use" src="https://img.shields.io/badge/use-research_%26_self--scan-C87D4F?style=flat-square"/>
  <img alt="Disclosure" src="https://img.shields.io/badge/disclosure-coordinated_only-7a5442?style=flat-square"/>
</p>

> **An open-source, outside-in replication of Anthropic's [Mythos Preview](https://red.anthropic.com/2026/mythos-preview/) / [Project Glasswing](https://www.anthropic.com/glasswing) — built around the publicly available [Claude Opus 4.7](https://github.com/anthropics/claude-code) model and runnable on commodity hardware.** Mythos Research Edition reproduces the eight-phase agentic vulnerability-discovery scaffold described in the April 2026 Glasswing announcement, at roughly **$0.30 – $1.50 per targeted scan** and without access to Anthropic's specialised model checkpoint. The scaffold has been deployed in coordinated-disclosure work that has surfaced multiple CVEs and GitHub Security Advisories across OSS projects.

> **For:** open-source maintainers self-scanning before release, security researchers running audits on projects they are authorised to audit, academic groups replicating the Mythos methodology, and individual researchers who cannot get on the Glasswing allow-list. **Not for:** mass scanning, MSP/MSSP managed-service workflows, or turn-key offensive use against unauthorised systems.

---

## What is Mythos Preview?

In April 2026 Anthropic released [`claude-mythos-preview`](https://red.anthropic.com/2026/mythos-preview/),
a model checkpoint trained for autonomous cybersecurity work — vulnerability discovery,
patch generation, black-box binary analysis, and long-running offensive-security agents.
The companion programme, [Project Glasswing](https://www.anthropic.com/glasswing), pairs the
model with critical-software maintainers to find and disclose vulnerabilities before the same
capabilities reach attackers. Anthropic's published Glasswing figures place per-run cost in
the **$20 – $50** range and report meaningful gains on OpenBSD and CyberGym benchmarks
relative to general-purpose baselines.

Mythos Preview is **invitation-only**. Access is allow-listed to roughly forty organisations
that build or maintain critical software, distributed via existing Anthropic / AWS Bedrock /
Google Vertex AI relationships. Anthropic does not currently plan a general release. The
model itself is paired with a comparatively simple agentic *scaffold* — language detection,
sink slicing, file ranking, an autonomous hunter, a sceptical validator, and (in the live
setting) an exploit-verification stage.

## What Mythos Research Edition is

This repository is an **outside-in replication of the scaffold half** of that programme.
The specialised model checkpoint is not available to us, so the discovery pipeline runs on
[`claude-opus-4-7`](https://github.com/anthropics/claude-code) — Anthropic's strongest
publicly available general-purpose model — via
[Claude Code CLI](https://github.com/anthropics/claude-code).

The replication asks one specific question:

> *Without the specialised checkpoint, can a faithful reproduction of the published scaffold,
> running on a general-purpose frontier model, recover a meaningful fraction of the
> vulnerability-discovery workflow described in the Mythos paper?*

The empirical answer, summarised: **yes for the discovery half, partially for live-exploit
development, and at roughly 25–50× lower cost per run**. The heaviest exploit-development
tasks — heap-shaping, CTF-grade chains, binary-only analysis — still favour the specialised
checkpoint. The discovery, ranking, sceptical-validation, and triage phases do not.

## What this is not

A few things, plainly:

- **Not a novel methodology.** Sink-guided slicing dates back to Semgrep / CodeQL / cppcheck /
  Coverity. The agentic-hunter pattern is contemporaneous work by many groups and is, at its
  core, the same pattern Anthropic describes in the Mythos paper. What this repository
  contributes is one openly runnable, end-to-end implementation of the pattern, pinned to a
  specific public frontier-model release that anyone can clone and reproduce.
- **Not the same model.** Mythos Preview's strongest published results depend on the
  specialised checkpoint. A general-purpose model is meaningfully weaker at the heavier end
  of exploit development; it is *not* meaningfully weaker at the discovery and triage end.
- **Not a turn-key exploitation framework.** The Phase 5 live-exec validator and the
  per-run PoC generators are held out of the public repository in line with
  coordinated-disclosure norms. The hook is public; the implementation is not.
- **Not an enterprise vulnerability-management platform.** Mythos is per-project,
  command-line, single-tenant. There is no scheduler, no fleet manager, no multi-tenant
  dashboard, no automated remediation, no MSP/MSSP integration.

## Mythos Preview vs Mythos Research Edition

|  | **Anthropic Mythos Preview** | **This: Mythos Research Edition** |
|---|---|---|
| Model | `claude-mythos-preview` (specialised checkpoint) | `claude-opus-4-7` (general-purpose) |
| Access | Invitation-only allow-list (~40 orgs) | Public, Apache 2.0 |
| Scaffold | Internal | Open-source (this repo) |
| Live exploit-development | Full pipeline | Phase-5 hook public, validator held private |
| Default scan scope | 1000-file projects (per published Glasswing runs) | Targeted (≤ 10 files default; configurable) |
| Per-run cost | $20 – $50 (per published Glasswing figures) | $0.30 – $1.50 |
| Best for | Allow-listed critical-infrastructure CVD | OSS self-audit, academic replication, individual researchers |
| Status (May 2026) | Held private; no application form | Available now, Apache-2.0, anyone with a Claude API key can run it |

## What it is good for

- **OSS maintainers self-scanning before release.** A repo-scoped scan with
  `--max-files 8 --pass-at-k 3` typically finishes for under $2 and surfaces 1–3 real
  candidate findings on a small-to-mid-sized library.
- **Academic replication of the Mythos scaffold.** The phases are documented, the prompts
  are versioned, the pipeline is deterministic up to model temperature, and a
  publication-ready PDF + LaTeX source ship in `dist/` and `paper/`. Compute is cheap
  enough to repeat at the dissertation-section level.
- **Coordinated-disclosure work** by individual researchers who cannot get on the Glasswing
  allow-list. The Research Edition has been used in published CVD work resulting in
  multiple CVEs and GitHub Security Advisories across OSS projects (see the author's
  [ORCID profile](https://orcid.org/0009-0000-6003-8826) and the
  [Wordfence Threat Intel researcher page](https://www.wordfence.com/threat-intel/vulnerabilities/researchers/keyvan-hardani)).

## What it is *not* good for

- **Heavy exploit-development work** against compiled binaries with modern mitigations.
  The general-purpose model gets *to* the bug; turning a primitive into a reliable
  weaponised chain is where the specialised checkpoint pulls away.
- **Mass scanning / managed-service workflows.** Mythos is per-project, terminal-driven.
  If you need an MSP-grade platform with multi-tenant dashboards and automated patching,
  this is the wrong repository.
- **Black-box or binary-only targets.** The pipeline assumes source-code access. Stripped
  binaries are out of scope.

## Deployment record (qualitative)

Across the operator's coordinated-disclosure work to date, the pipeline has surfaced
at least one validator-confirmed candidate finding on every audited target. The target
record covers OSS libraries in C/C++, Python, PHP, JavaScript/TypeScript; embedded
firmware codebases; Linux kernel-side modules; PHP/Node server applications; and
web-application targets audited with operator authorisation. Specific projects, advisory
identifiers, and finding details are deliberately not enumerated here in line with
coordinated-disclosure norms; the public record lives at the
[Wordfence Threat Intel researcher page](https://www.wordfence.com/threat-intel/vulnerabilities/researchers/keyvan-hardani),
on the operator's [ORCID profile](https://orcid.org/0009-0000-6003-8826), and surfaces in
the repository's `disclosures/` directory as embargoes lift.

This is reported as a qualitative observation, not a controlled hit-rate: target selection
in the operator's CVD workflow is not random, and the scaffold's design biases toward
high-yield projects via the file-ranking phase. What can be claimed in good faith is that
the pipeline has not returned an empty report on any audited target in the deployment
record to date, that this generalises across the language families and target types
listed above, and that the finding-yield is robust enough that the operator's CVD
workflow uses the public scaffold as the discovery stage by default.

## Held-private extensions (not in this repository)

The Research Edition is the public, finding-first subset of a larger toolchain. The
held-private extension is what turns a discovered candidate into a substantiated
advisory — it is what the operator's published CVEs and security advisories run on
in combination with the public Research Edition. The phases below are documented
here for reproducibility of the capability claim. **The orchestrator scripts, prompts,
and per-platform exploit-development modes are not released.**

| Phase | Capability |
|---|---|
| **5a — Exec-primitive labelling** | Maps each finding to a reachable primitive: arbitrary read, controlled write, control-flow hijack, authentication bypass, SQL data dump, path traversal, internal SSRF. |
| **5b — Chain construction** | Combines primitives toward concrete capability goals: pre-authentication RCE, privilege escalation, sandbox escape. |
| **5c — Reliability testing** | Runs N independent trials per chain; emits `RELIABLE / FLAKY / UNRELIABLE`. |
| **5d — Mitigation enumeration** | Per-OS, per-mitigation enumeration (ASLR, DEP, CFI/CFG, PatchGuard, HVCI, PAC/PPL, AMFI/SIP, KASLR, SMEP, SMAP, PTI, stack-protector variants) for severity calibration. |
| **5e — Sandbox-escape patterns** | Renderer-to-broker, container-to-host, jail-to-host, seccomp-filter abuse, container-runtime descriptor-leak patterns. |
| **5p — Platform-exploit dispatcher** | Per-platform exploit-development modes (web, Windows, macOS, mobile, network, kernel) backed by a Kali-based ephemeral analysis sandbox. |
| **R — Recon** | Optional broad-pass enumeration, used only when the operator's CVD authorisation explicitly extends to external attack surface. |

These are deliberately omitted from the public artefact in line with coordinated-disclosure
norms — to keep this repository a *research scaffold* rather than a turn-key offensive
framework. Substantive collaboration on the held-private extension is possible under
explicit research-partnership terms; contact the operator if your work falls within that
scope.

## Pipeline

The current default (`scripts/mythos-v4.sh`) runs eight phases. Phases 0–4, 6, and 7 are
open in this edition. **Phase 5 (live-exec validation) is held private** and not included —
see [Scope](#scope). v3.1 (`scripts/mythos-v3.sh`) remains available as the seven-phase
fallback used in the original report.

- **Phase 0 — Language detection.** Dominant language of the target tree → selects a language-specific
  *vulnerability-semantics prompt* (`prompts/vsp-<lang>.md`).
- **Phase 1 — Sink-guided slicing.** A language-specific sink catalog (`scripts/lib/sinks/*.txt`) is
  ripgrep'd across the target, producing an NDJSON of `{category, pattern, file, line, snippet}` hits.
- **Phase 2 — File ranking.** Files are tiered by sink-category density. High-yield categories
  (deserialization, code-eval, SQL injection, prototype pollution, XXE, framework footguns, sanitiser
  gaps, browser-API footguns) dominate; files whose matches are all in `SAFE_*` variants are demoted.
- **Phase 2.5 — Build sandbox** *(v4)*. `lib/build-sandbox.sh` prepares a per-scan scratch
  directory with the target compiled (ASan if C/C++, venv + pip if Python, npm install if
  Node). Hunters get scoped Bash + Edit + Write inside the scratch dir and read-only Read
  on the source tree. Skip with `--no-build-sandbox`.
- **Phase 3 — Agentic hunt.** One Claude-Code subagent per top-ranked file, parallelised. In
  v4 the hunter brief (`prompts/hunter-agent-live.md`) instructs the agent to test
  hypotheses against the live build instead of tracing statically. v4 also exposes
  `--prompt-style minimal` (`prompts/hunter-agent-minimal.md`) for an A/B against the
  Mythos-Preview-style minimal prompt.
- **Phase 3.5 — Adversarial self-challenge** *(v4)*. Each finding is fed back to a fresh
  agent with `prompts/self-challenge.md` asking for the strongest counter-argument. Findings
  flagged `ADVERSE` are dropped before validation. Skip with `--no-self-challenge`.
- **Phase 4 — Skeptical validation.** A second-pass agent re-reads the source and the
  finding with an explicit *skeptical reviewer* framing. In v4 the validator pre-loads
  cross-session false-positive memory from `dismissals/<target_id>.json` so the same FP is
  not re-flagged across runs. Output:
  `CONFIRMED | FALSE_POSITIVE | DOWNGRADED | NEEDS_MORE_INFO`.
- **Phase 6 — Aggregate.** JSON summary with severity breakdown, per-phase cost telemetry, and the
  validator verdict for each finding.
- **Phase 7 — FP-memory writeback** *(v4)*. Persists this run's `FALSE_POSITIVE` and
  `ADVERSE` markings into `dismissals/<target_id>.json` (scoped per target via the
  realpath SHA-256), so future runs against the same target avoid re-discovering them.

### Optional companion utilities

- **`scripts/mythos-commit.sh`** — SHA-3-256 commitment scheme for unpatched-bug
  accountability. Lets you publish a hash now and reveal the finding later, mirroring
  the pattern from the published Mythos paper.
- **`prompts/patch-gen.md`** — given a finding, drafts a minimal-correct fix as a
  git-applyable diff plus a regression test that fails without the patch.
- **`prompts/disclosure-writeup.md`** — vendor-ready report templates per channel
  (GHSA, HackerOne, CVE, Bugzilla, vendor-email, oss-security).
- **`prompts/mitigation-map.md`**, **`prompts/reliability-test.md`** — defensive analysis
  helpers for severity calibration and finding-stability QA.

## Per-run cost

Mythos targeted scans (≤ 10 files, `--budget 3.00` per hunter) land at **$0.30 – $1.50 per run** on
`claude-opus-4-7`. Anthropic's published Glasswing runs on `claude-mythos-preview` are in the
**$20 – $50** range per run. The gap is mostly the scope (1000 files vs 8) and the model
choice (internal preview vs general-purpose). For self-scanning an individual OSS project, the
cheap end is sufficient.

## Diversity seeding

Anthropic's key insight is that sampling diverse traces from the same input dramatically increases
bug-discovery breadth. Mythos v3 adapts this with **`--pass-at-k K`**: K independent hunter runs per
file, each seeded with a different *focus hint* drawn from (a) the sink categories present in the file,
(b) lengthy function names (rough entry-point heuristic), and (c) input markers (`@app.route`,
`socket.on`, `req.body`).

Empirically: `K = 2..3` catches distinct classes of findings in the same file without exploding cost.
`K = 1` is the v2-compatible default. v4 raises the default to `K = 3` because the
build-sandbox phase already amortises the cache-warm cost across the K runs.

## Quick start

```bash
# 1) clone
git clone https://github.com/Keyvanhardani/mythos-research.git
cd mythos-research

# 2) make sure Claude Code CLI is available
claude --version

# 3) v4 (default since v2.0) — eight-phase pipeline with build sandbox,
#    self-challenge, and cross-session FP memory
bash scripts/mythos-v4.sh /path/to/target --max-files 8 --budget 3.00

# optional: minimal prompt style (Mythos-Preview-paper baseline for A/B)
bash scripts/mythos-v4.sh /path/to/target --prompt-style minimal

# optional: drop the build-sandbox phase (e.g. for languages without a build step)
bash scripts/mythos-v4.sh /path/to/target --no-build-sandbox

# optional: drop self-challenge (faster, ~25 % cheaper, more false positives)
bash scripts/mythos-v4.sh /path/to/target --no-self-challenge

# v3.1 fallback — seven-phase pipeline, no live tools, no FP memory.
# Used in the original Research Edition report.
bash scripts/mythos-v3.sh /path/to/target --max-files 8 --budget 3.00
```

Reports land in `reports/<scan-id>/summary.json` and per-file `findings/` + `validated/` JSONs.

## Scope

**In scope for this repository:** finding-first pipeline, sink catalogues, ranker, hunter & validator
prompts, the seven-phase orchestrator, the diversity-seeding driver, a light hybrid-tools wrapper for
combining classical static analysis with the agentic pass.

**Out of scope — held private:** the Phase 5 live-exec validator (`exec-validator.sh` + its prompt),
the exploit-sketch stage (`exploit-sketch.md`), per-run PoC generators, and any target-specific tuning
accumulated during real scans. These are kept outside this repository to keep Mythos a **research
scaffold**, not a turn-key exploitation framework.

If Phase 5 is referenced in `mythos-v3.sh`, the script detects the missing `exec-validator.sh` and
automatically skips it with a clear notice — no errors, no half-runs.

## Responsible disclosure

This is a security-research tool. The intended uses are:

- OSS maintainers self-scanning their own projects before release
- Security researchers running Mythos over projects they have authorisation to audit
- Academic replication of Anthropic's methodology

If Mythos surfaces a real vulnerability, please follow the upstream project's coordinated-disclosure
process. Do **not** publish PoCs before the vendor has acknowledged and patched.

See [`SECURITY.md`](SECURITY.md) for details.

## Limitations

- **Sink catalogues are not exhaustive.** The GLib / GObject / json-glib family in particular is not
  yet covered in `sinks/c-cpp.txt`; PRs welcome.
- **Ranker bias toward small, high-sink-density files.** Mega-files (> 2500 LOC) are currently
  skipped — that's a meaningful gap for large parser files.
- **Model matters.** `claude-opus-4-7` is a strong general model but the heaviest exploit-development
  tasks in Anthropic's Glasswing report were done on `claude-mythos-preview`, a specialised
  checkpoint not publicly available. Expect Mythos to be better at *finding* than at *exploiting*.
- **No Docker isolation yet.** Hunters read the target tree directly; running against untrusted
  codebases locally is at your own risk.

## Evolution (version history)

Mythos went through four scaffolded iterations — all are present for pedagogical reference:

- **`scripts/archive/mythos-scan.sh`** — v1, original main orchestrator. Simpler, no
  sink-slicer.
- **`scripts/archive/mythos-v2.sh`** — v2, adds sink-slicing + ranker + skeptical validator.
- **`scripts/mythos-v3.sh`** — v3 (basis of the original Research Edition report). Adds
  per-run diversity seeding, pass@k, per-phase cost telemetry, and the Phase 5 hook
  (held private).
- **`scripts/mythos-v4.sh`** — v4 / **current default since v2.0**. Adds Phase 2.5 build
  sandbox, Phase 3 live-exploration hunters with scoped Bash/Edit/Write, Phase 3.5
  adversarial self-challenge, cross-session false-positive memory, and Phase 7
  dismissals writeback. Companion `mythos-commit.sh` adds SHA-3-256 finding commitment.
- **`scripts/archive/pass-at-k.sh`** — the v2-era standalone diversity driver; in v3+ this is folded
  into the main orchestrator via `--pass-at-k K`.

See [`CHANGELOG.md`](CHANGELOG.md) for the prose version.

## Acknowledgements

Mythos Research Edition is an **outside-in replication** of Anthropic's published research:

- **Project Glasswing** / `claude-mythos-preview` — Anthropic's red-team research release, April 2026.
  [red.anthropic.com/2026/mythos-preview/](https://red.anthropic.com/2026/mythos-preview/)

The sink-catalog approach draws on decades of static-analysis practice (Semgrep, CodeQL, cppcheck,
Coverity); the agentic-hunter shape is contemporaneous work by many groups and is, at its core, the
same pattern Anthropic describes in their paper.

## Further reading

- [`RESEARCH.md`](RESEARCH.md) — full research analysis: what Glasswing actually does, the benchmark
  gap, what scaffolding can and cannot close, prompting techniques that work, multi-agent patterns.
- [`dist/Mythos-Research-Edition.pdf`](dist/Mythos-Research-Edition.pdf) — the report
  as a publication-ready PDF.
- [`paper/`](paper/) — arXiv-ready LaTeX source (`paper.tex` + `references.bib` + `Makefile`).
- [`scripts/V3_DESIGN.md`](scripts/V3_DESIGN.md) — v3 design doc (goals, deltas to v2, metrics).

## Cite

If you use Mythos Research Edition in academic or professional work, please cite the report and the
repository. A machine-readable `CITATION.cff` is provided at the repository root; GitHub renders a
"Cite this repository" button from it. Suggested BibTeX:

```bibtex
@techreport{hardani2026mythosResearch,
  author       = {Hardani, Keyvan},
  title        = {An Outside-In Replication of Project Glasswing: Mythos Research Edition},
  institution  = {Independent},
  year         = {2026},
  month        = apr,
  doi          = {10.5281/zenodo.19727857},
  url          = {https://doi.org/10.5281/zenodo.19727857},
  note         = {ORCID 0009-0000-6003-8826.
                  Concept DOI (always-latest). For version-specific citation:
                  10.5281/zenodo.20022293 (v2.0.0, current),
                  10.5281/zenodo.19727858 (v1.0.2).}
}
```

## License

Apache License 2.0. See [`LICENSE`](LICENSE).

The licence permits use, modification, and redistribution for lawful purposes, including
commercial use. Use against systems without explicit authorisation is outside the intended
scope. Coordinated disclosure is expected for any vulnerability surfaced with the help of
this scaffold.

## Author

**Keyvan Hardani** — Applied AI Researcher · Engineer.
[keyvan.ai](https://keyvan.ai) · [github.com/Keyvanhardani](https://github.com/Keyvanhardani) · [linkedin.com/in/keyvanhardani](https://linkedin.com/in/keyvanhardani) · ORCID [0009-0000-6003-8826](https://orcid.org/0009-0000-6003-8826) · [hello@keyvan.ai](mailto:hello@keyvan.ai)
