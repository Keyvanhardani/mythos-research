# Contributing to Mythos Research Edition

Thanks for considering a contribution. Mythos is research-grade scaffolding — small, honest PRs
are very welcome, and the bar for "this is a useful addition" is concrete-and-testable, not
rhetorical.

## Ground rules

1. **Coordinated disclosure only.** If your PR is motivated by a finding you've made with Mythos,
   make sure the finding is either patched upstream, publicly disclosed, or clearly anonymised.
   Do not submit sink patterns that would only be useful to attack still-embargoed vulnerabilities.
2. **No target-specific code.** Sink catalogues, prompts, and heuristics should be generic. Avoid
   naming specific projects, vendors, or individuals in patterns or examples.
3. **Apache 2.0.** By submitting a PR you agree to license your contribution under Apache License 2.0.

## What we welcome

- **Sink-catalogue extensions**: GLib / GObject / json-glib for C; Django / Flask / FastAPI
  middleware for Python; Laravel / Symfony patterns for PHP; framework-specific patterns for
  JS/TS.
- **New language support**: Go, Rust, Ruby, Kotlin. Start with a `prompts/vsp-<lang>.md` + a
  `scripts/lib/sinks/<lang>.txt`.
- **Ranker improvements**: attack-surface heuristics beyond raw sink density (public-facing
  routes, auth-adjacent modules, serialisation boundaries).
- **Validator prompt tuning**: smaller false-positive rate on sanitised code paths.
- **Benchmark / reproducibility work**: a fixture set of synthetic vulnerable and clean projects,
  with expected-output JSON, to run Mythos against as a regression suite.
- **Docker isolation**: a simple `--docker IMAGE` flag that runs hunters against the target in
  a disposable container.

## What we will NOT merge

- Live-exploit tooling, PoC generators, or anything that turns findings into working exploits.
  Mythos Research Edition is deliberately a finding-first scaffold; weaponisation is out of scope
  and will stay out of scope.
- Patterns that only make sense against a specific named project that has not publicly patched.
- Marketing-driven copy changes to the README or RESEARCH.md.
- Dependencies on paid or proprietary services beyond Claude Code CLI itself.

## How to open a good PR

1. **One change per PR.** A new sink language is one PR; a ranker improvement is another.
2. **Include a short empirical note.** "Ran against projects A, B, C. Before: X findings.
   After: Y findings. New TPs: <list>. New FPs: <list>." A rough note is fine.
3. **No force-pushes after review.** Add fixup commits; squash on merge if requested.

## Questions

Open a Discussion or email hello@keyvan.ai — responses within a couple of days on weekdays.
