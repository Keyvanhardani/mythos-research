# Security Policy

## Scope

Mythos Research Edition is a vulnerability-discovery *scaffold*, intended for:

- Open-source maintainers scanning their own projects
- Security researchers running Mythos over projects they have explicit authorisation to audit
- Academic replication of Anthropic's [claude-mythos-preview](https://red.anthropic.com/2026/mythos-preview/) methodology

Mythos does **not** include:

- Live-exploit generation
- PoC compilation / execution
- Any sanctioning of use against third-party systems without authorisation

## Reporting a vulnerability in Mythos itself

If you find a security issue in this scaffold (e.g., a prompt-injection vector against the hunter
agent, a path-traversal in the orchestrator, leakage of target file contents outside the report
directory), please do **not** open a public issue.

Email the maintainer directly at **hello@keyvan.ai** with:

- A short description of the issue
- Steps to reproduce, ideally against a dummy target tree
- Your preferred attribution for any resulting advisory

You will get an acknowledgement within 72 hours. Coordinated disclosure timelines are negotiable on
a per-case basis.

## Reporting a vulnerability Mythos helped you find

**This is a coordinated-disclosure tool.** If Mythos surfaces a real vulnerability in a third-party
project, the expectation is:

1. **Do not publish a PoC** until the upstream vendor has acknowledged and patched.
2. **Use the upstream project's preferred channel** — GHSA, the project's SECURITY.md, the vendor's
   security email, or a bug-bounty programme.
3. **Give vendors a reasonable window** (typically 90 days, extendable on request).
4. **Credit responsibly** — name the vendor's response if they were professional; avoid naming
   individual maintainers without consent.

If you use Mythos output in a publication, we'd appreciate (but do not require) a citation or a
mention in the acknowledgements.

## Misuse

Using Mythos against systems you have no authorisation to audit is both unlawful in most
jurisdictions and against the letter and spirit of this repository.  The maintainers reserve
the right to refuse collaboration, PRs, or credits from parties who demonstrably use this
scaffold for unauthorised testing.

## Limitations you should be aware of

- **Hunter agents have `Read`, `Grep`, `Glob`, and `Bash` tools.** They can and do execute
  `rg`, `find`, and `grep`-style commands on your local filesystem. Run against trusted code only,
  or inside a container / VM if the target is untrusted.
- **Claude Code CLI** is required and will make outbound API calls to Anthropic for inference. If
  that is not acceptable in your environment, do not use Mythos there.
- **Phase 5 (live-exec)** is held private. This is deliberate. The repository will not be extended
  to include weaponised stages.
