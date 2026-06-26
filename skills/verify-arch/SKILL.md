---
name: verify-arch
description: Use to verify the assembled, running product delivers each designed capability on its declared entry point, user-reachable. Integration-level fitness function. Reads ONLY the Interface-Placement Map (registry), never the build plan or implementation. Run by a different agent than the builder.
---

# verify-arch — integration fitness function

You are given ONLY: the Interface-Placement Map (see `registry-schema.md`) and the running product's entry (URL / CLI binary / base endpoint / import path). You are FORBIDDEN to read the build plan or implementation — derive every check from the registry alone.

For EACH Cap-ID, look up the entry-point type and drive the assembled product:

| Entry-point type | Driver | human-factors plugin |
|---|---|---|
| UI (web page) | real browser / Playwright | invoke `skill-ui-human` |
| CLI (command) | run the command, read stdout / exit code | cli-dx rubric |
| API (endpoint) | http client, read response / status | cognitive-dimensions |
| library (function) | call the public API, read return | lib-dx rubric |

Look up the row; do NOT guess. If the entry point is a Web UI, invoke `skill-ui-human`; otherwise use the row's plugin.

Navigate the declared **reachable_path** on the declared **entry_point**, perform the **acceptance_example**, observe the output, then emit exactly one verdict per Cap-ID:

- MATCHES — drove the declared path on the declared entry point, performed the example, observed the declared output, human-factors bar met.
- PARTIAL — present and reachable, example only partly satisfied.
- MISSING — not performable anywhere.
- MISPLACED — performable, but NOT on the declared entry point / not via the user path (wrong place, or only via a buried path).
- BLOCKED — harness/auth blocked reaching it (not MISSING); route to a human.

Evidence (required): for each verdict emit `{cap_id, verdict, route_taken, assertion, evidence_path, evidence_ts}`. A verdict with no observed-output assertion is itself a failure (verify-lint).

Write all verdicts to `verdicts.json` (`{"results": [ ... ]}`), consumed by `lib/verify_coverage.py`.
