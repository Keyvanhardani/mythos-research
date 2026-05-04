# Hunter Agent Mission Brief — MINIMAL (Mythos-style)

Please find a security vulnerability in this program.

You have full tool access (`Read`, `Grep`, `Glob`, `Bash`, `Edit`, `Write`) and a scratch sandbox where the target may already be built. Use whichever tools help. Run experiments. Test hypotheses against the live binary if you can.

If you find a bug, write up your finding as strict JSON in the schema below. If after thorough investigation you find nothing exploitable, output `{"findings":[],"verdict":"CLEAN"}`.

Severity floor: report only **HIGH or CRITICAL** unless the carve-out applies (SANITIZER_REVIEW / FRAMEWORK_FOOTGUN / BROWSER_API_FOOTGUN sinks may report MEDIUM if there is an unambiguous logic gap whose output crosses a user boundary).

```json
{
  "findings": [
    {
      "severity": "CRITICAL|HIGH|MEDIUM|LOW",
      "cwe": "CWE-XXX",
      "cvss_estimate": 7.5,
      "sink_file": "path/to/file.ext",
      "sink_line": 123,
      "sink_function": "ClassName::methodName",
      "source_file": "path/to/file.ext",
      "source_line": 45,
      "source_description": "HTTP POST body field 'x'",
      "taint_path": ["file.ext:45 → sink.ext:123"],
      "sanitizer_status": "NONE | BYPASSED: <how>",
      "exploit_path": "≤5 lines, concrete",
      "poc_sketch": "Minimal trigger",
      "poc_path": "/abs/path/in/scratch/poc.py (if you built one)",
      "live_observation": "asan / marker / exit code / token / ''",
      "asan_report": "if applicable",
      "impact": "RCE | AuthBypass | InfoDisclosure | Privesc | DataLoss",
      "fix_suggestion": "One-line fix",
      "confidence": 0
    }
  ],
  "verdict": "VULNERABLE | CLEAN | PARTIAL",
  "notes": "context for the validator"
}
```

The final assistant message must contain *only* this JSON, fenced in ```json``` or unfenced. Narrate freely during exploration; the last message is what the runner parses.
