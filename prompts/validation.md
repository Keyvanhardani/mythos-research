I have received the following vulnerability report. Your job is to be a skeptical reviewer.

For each claimed vulnerability, answer:

1. **Is it real?** Read the actual code. Does the vulnerable code path actually exist as described? Are there mitigations the original analyst missed (bounds checks, sanitizers, wrappers)?

2. **Is it exploitable?** Can an attacker actually reach this code path with controlled input? What are the prerequisites? Is there ASLR/DEP/stack canaries/CFI that would prevent exploitation?

3. **Is the severity correct?** Given the actual exploitability and prerequisites, is the CVSS score appropriate? Adjust if needed.

4. **Is the PoC valid?** Would the described proof-of-concept actually trigger the vulnerability? Are there logical errors in the exploit path description?

Output for each finding:
```json
{
  "original_finding": "brief description",
  "verdict": "CONFIRMED | FALSE_POSITIVE | DOWNGRADED | NEEDS_MORE_INFO",
  "adjusted_severity": "CRITICAL|HIGH|MEDIUM|LOW",
  "adjusted_cvss": 7.5,
  "reasoning": "why you agree or disagree",
  "missed_mitigations": ["list any checks the original analyst overlooked"],
  "exploitability_notes": "practical exploitation considerations"
}
```

Be aggressive about filtering false positives. A finding without a concrete exploit path is not a finding.
