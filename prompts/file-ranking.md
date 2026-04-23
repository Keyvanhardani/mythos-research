You are a vulnerability researcher performing initial triage of a codebase.

Rate every source file on a 1-5 vulnerability likelihood scale:

1 = Constants, enums, type definitions, generated code — virtually no risk
2 = Internal utilities, string helpers, logging — low exposure  
3 = Business logic, state machines — moderate risk, logic bugs possible
4 = Input parsing, database queries, authentication, serialization — high risk
5 = Internet-facing protocol parsers, raw network data handling, cryptographic implementations, privilege boundaries — critical risk

For each file, output ONE line:
```
RANK | filepath | reason (max 10 words)
```

Sort by rank descending (5 first). Only include rank 3-5 files.

Focus on files that:
- Parse untrusted input (network packets, file formats, user data)
- Handle authentication or authorization decisions
- Perform memory allocation based on external input
- Implement cryptographic operations
- Cross privilege boundaries (user→kernel, sandbox→host, guest→host)
