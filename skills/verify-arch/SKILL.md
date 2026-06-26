---
name: verify-arch
description: Use AFTER build, BEFORE collapsing a multi-entry-point project as "done". Drives the assembled running product against the Interface-Placement Map to confirm each capability is wired into its declared entry point and reachable. ASPICE SWE.5 (Software Integration & Integration Test) — cheap surface-presence check, NOT the full user-outcome check (that's verify-spec / SWE.6). Single-entry-point projects: N/A — skip this skill.
---

# verify-arch — integration fitness function (SWE.5)

## When to use
Multi-entry-point projects only (the spec's `## Surfaces` has ≥2 rows). Run AFTER `subagent-driven-development` finishes the build, BEFORE collapsing the project as done. For single-entry projects, skip — there's no cross-surface integration to verify; go straight to `verify-spec`.

## What you check vs what verify-spec checks
| | This skill (SWE.5) | verify-spec (SWE.6) |
|---|---|---|
| Referent | Interface-Placement Map (architecture) | Capability Registry acceptance examples (requirements) |
| Question | "Is the capability **wired into the declared entry point**, reachable?" | "Does the capability **deliver the user outcome**?" |
| Test cost | Cheap — presence/reachability check; no full user flow needed | Full — drive the entire acceptance example |
| Catches | MISPLACED, MISSING, unreachable | wrong behavior, partial behavior |
| Example | "Is `#curator-panel` present on `reading.html`?" | "Ask 'X?' → does a card appear in the panel?" |

Both fire in a complete pipeline. SWE.5 first (cheap, catches placement bugs early); SWE.6 second (expensive, catches behavior bugs).

## Independence (load-bearing — do NOT break)
You are given ONLY:
- the Interface-Placement Map (see `registry-schema.md` for shape), and
- the running product's entry (URL / CLI binary / base endpoint / import path).

You are **FORBIDDEN to read the build plan or the implementation source**. Derive every check from the map alone. This is the V-model's right-arm independence (builder ≠ verifier).

## How to check each Cap-ID
Look up the row in the map; drive accordingly. Look up — do NOT guess.

| entry_type | Driver | Usability rubric (if applicable) |
|---|---|---|
| UI (web page) | real browser / Playwright; navigate the declared `reachable_path`, look for the declared marker | invoke `skill-ui-human` |
| CLI (command) | run the declared command; read stdout + exit code | judged from the registry's `acceptance_example` (e.g. "help shows --out flag, exit 0") |
| API (endpoint) | http client; read response + status | judged from the registry's `acceptance_example` |
| library (function) | call the public API; read return value | judged from the registry's `acceptance_example` |

(No separate "human-factors" dispatch layer — UI goes direct to `skill-ui-human`; non-UI surfaces encode their bar in `acceptance_example` itself.)

## Emit one verdict per Cap-ID

- **MATCHES** — drove the declared path on the declared entry point, observed the declared marker/output. (UI usability bar via skill-ui-human must also pass for UI.)
- **PARTIAL** — present and reachable, only partly satisfies the marker.
- **MISSING** — not performable anywhere.
- **MISPLACED** — performable, but NOT on the declared entry point / not via the declared path (wrong surface, or only via a buried route).
- **BLOCKED** — harness/auth blocked reaching it (≠ MISSING); route to a human.

**Required evidence per verdict:** `{cap_id, verdict, route_taken, assertion, evidence_path, evidence_ts}`. A verdict with no observed-output assertion is itself a defect (verify-lint).

Write all verdicts to `verdicts.json` (`{"results": [...]}`), consumed by `~/.claude/lib/verify_coverage.py` (set-difference → completion gate).
