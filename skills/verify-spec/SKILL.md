---
name: verify-spec
description: Use to verify the assembled, running product delivers each capability's user OUTCOME from the spec's acceptance examples. Acceptance-level fitness function. Reads ONLY the Capability Registry acceptance examples; FORBIDDEN to read the build plan or implementation. Run by a different agent than the builder.
---

# verify-spec — acceptance fitness function

Given ONLY the Capability Registry (`acceptance_example` per Cap-ID) and the running product entry. You are FORBIDDEN to read the build plan or implementation.

For each Cap-ID, drive the assembled product as a real user and assert the `acceptance_example`'s observable output. Emit one verdict per Cap-ID (MATCHES / PARTIAL / MISSING / MISPLACED / BLOCKED) with evidence, into `verdicts.json` for `lib/verify_coverage.py`. For UI entry points, invoke `skill-ui-human` for the human-factors bar.
