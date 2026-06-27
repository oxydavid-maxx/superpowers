---
name: verify-spec
description: Use AFTER build (and AFTER verify-arch for multi-entry projects) to verify the assembled running product DELIVERS each capability's user outcome per the spec's acceptance_example. ASPICE SWE.6/SYS.5 (Qualification Test) — full user-flow check against requirements, NOT the cheap surface-presence check (that's verify-arch / SWE.5). Fires for every project (single-entry or multi-entry).
---

# verify-spec — acceptance / qualification fitness function (SWE.6 / SYS.5)

## When to use
Every project, after build. For multi-entry projects, run AFTER `verify-arch` (let the cheap surface check fail fast first). For single-entry projects, this is the only right-arm verify needed.

## What you check vs what verify-arch checks
| | verify-arch (SWE.5) | This skill (SWE.6) |
|---|---|---|
| Reads | Registry `entry_point` + `reachable_path` (placement) | Registry `acceptance_example` (behavior) |
| Question | "Is it WIRED to the right surface?" | "Does it DELIVER the user outcome?" |
| Cost | Cheap (presence/reachability) | Full (drive the entire acceptance example) |

**Concrete contrast on the SAME Cap-ID:**

```
Cap-ID: CAP-01  capability: "Sediment a Q&A into an atomic card"
entry_point: reading.html  acceptance_example: ask "what is X?" → card with "X" + link to source paragraph appears in #curator-panel

verify-arch asks:   Is #curator-panel present on reading.html?              (cheap; passes iff the panel is there)
verify-spec asks:   On reading.html, ask "what is X?" — does a card with    (full flow; passes iff the example is satisfied)
                    "X" + correct paragraph link actually appear in the panel?
```

You can have a passing verify-arch + failing verify-spec (panel exists but doesn't work correctly). That's the value of running both.

## Independence (load-bearing — do NOT break)
You are given ONLY:
- the Capability Registry's `acceptance_example` per Cap-ID, and
- the running product's entry (URL / CLI binary / base endpoint / import path).

You are **FORBIDDEN to read the build plan or implementation source**. Derive every check from the acceptance_example alone. Right-arm independence (builder ≠ verifier).

## How to check each Cap-ID
Drive the running product as a real user would, perform the `acceptance_example`'s input, assert the example's observable output.

| entry_type | Driver | Usability rubric (if UI) |
|---|---|---|
| UI | real browser / Playwright | invoke `skill-ui-human` for UX bar |
| CLI | shell; perform input; assert stdout + exit | bar is embedded in `acceptance_example` |
| API | http client; perform request; assert response + status | bar embedded |
| library | call the public API; assert return | bar embedded |

## Emit one verdict per Cap-ID
- **MATCHES** — performed the example, observed the declared output. UI usability bar (via skill-ui-human) also met.
- **PARTIAL** — example partially satisfied (e.g., card appears but link is wrong).
- **MISSING** — example cannot be performed (the user-visible behavior is absent).
- **BLOCKED** — harness/auth blocked the run; route to a human.

(verify-spec does NOT emit MISPLACED — placement is verify-arch's domain. If the capability is on the wrong surface, verify-arch already flagged it.)

**Required evidence per verdict:** `{cap_id, verdict, input_performed, observed, evidence_path, evidence_ts}`. A verdict with no observed-output assertion is itself a defect.

Write all verdicts to `verdicts.json` (`{"results": [...]}`), consumed by `~/.claude/lib/verify_coverage.py`.
