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

## Acceptance examples are structured (BDD / Specification by Example)
Each `acceptance_example` is authored as **given / when / then** — given a state, when an input, then an observable output. Plain language is fine, but all three parts must be present and concrete; a vague example ("works correctly") is a spec defect, not something you can drive. You COMPILE the given/when/then into a runnable driver (Playwright / shell / http) at verify time — you do not invent what to test, you execute the pre-authored example.

## How to check each Cap-ID
Drive the running product as a real user would, perform the `acceptance_example`'s `when` input, assert the `then` observable output.

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
- **BLOCKED** — harness/auth/tool unavailable; you could NOT perform the example. Route to a human.

**Fail-closed (load-bearing — never degrade):** if the driver/tool you need is unavailable (browser won't start, no auth, harness missing), the verdict is **BLOCKED**, never MATCHES. "HTTP 200" / "the file exists" / "the test compiled" is NOT evidence the user outcome was delivered. A tool you can't run means the capability is **unverified = not done**, routed to a human — it is never silently downgraded to a pass. (This is the 478-green-tests-broken-UI failure mode.)

**The browser-MCP-down escape hatch is FORBIDDEN.** "claude-in-chrome is unavailable → mark UNVERIFIED" is NOT fail-closed — it is a dodge. `UNVERIFIED` is not a verdict. When the browser MCP is down, reach for **Playwright headless** (a real Chromium: fresh context, zero cache) and drive the page for real. Only when there is NO usable driver at all — MCP down AND Playwright unavailable — is the verdict BLOCKED→human. (Incident 2026-06-28: Playwright sat installed in a sibling venv, named by verify-arch, while a verify plan standardized "視覺 UNVERIFIED" for every UI item.)

**UI evidence must be of the DEPLOYED surface.** Render and assert against the real user-facing URL (the deployed host), not localhost — a local render can pass while the user's CDN/cache serves a stale, broken asset (incident: CF edge-cached old CSS). Store the screenshot as `evidence_path` + the `evidence_url`; localhost evidence on a deployed capability is not a pass.

**UI MATCHES requires `ui_human_evidence`.** For any UI Cap-ID marked MATCHES, include machine-readable `ui_human_evidence` with screenshots, viewport/overflow checks, touch target metrics, keyboard focus evidence, feedback states, and console/page error cleanliness. `skill-ui-human` is the required dependency for this human-facing evidence bar; if it is unavailable, the UI verdict is BLOCKED, not MATCHES.

**Edit / save capabilities require a round-trip assertion.** For any capability that persists (edit, save, write), the case must: perform the edit → reload/re-read the same artifact → assert **the field you changed changed AND a declared invariant set is untouched** (e.g. "body updated AND frontmatter preserved"). Asserting only "saved" misses silent collateral damage (incident: frontmatter was clobbered on save).

(verify-spec does NOT emit MISPLACED — placement is verify-arch's domain. If the capability is on the wrong surface, verify-arch already flagged it.)

**Required evidence per verdict:** `{cap_id, verdict, given, when_performed, then_expected, observed, evidence_path, evidence_ts}`. UI MATCHES verdicts additionally require `ui_human_evidence`. A verdict with no observed-output assertion is itself a defect.

Write all verdicts to `verdicts.json` as `{"head_sha": "<git HEAD at verify time>", "results": [...]}`, consumed by `~/.claude/lib/verify_coverage.py`. The `head_sha` binds the verdicts to the exact commit verified — `R-PIPE-VERIFY-FINISH` treats verdicts whose `head_sha` ≠ current HEAD as stale (you must re-verify after any further commit).
