---
name: verification-before-completion
description: Use when about to claim work is complete, fixed, or passing, before commit, merge, publish, or PR, especially when deciding whether prior exact-bound PASS evidence is still valid
---

# Verification Before Completion

## Overview

Claiming work is complete without verification is dishonesty, not efficiency.

**Core principle:** Exact-bound evidence before claims, always.

Evidence freshness is a property of its result-affecting input bindings, not its age or
whether the command happened in the current message.

**Violating the letter of this rule is violating the spirit of this rule.**

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT VALID EXACT-BOUND PASS EVIDENCE
```

A prior PASS receipt may remain valid across candidate commits when its exact action key
and every result-affecting input binding are identical. An incomplete binding is not
reusable evidence.

## Receipt Validity Contract

An action receipt binds at least the command and selected tests, working directory,
toolchain and dependency identity, relevant environment, configuration, fixtures, and
all source or generated inputs that can change the result.

| Observation | Decision |
|-------------|----------|
| Exact action key + every result-affecting input binding match | Reuse the PASS receipt, even across candidate commits |
| Candidate metadata changed but every result-affecting binding is identical | Rebind the receipt to the candidate proof map; do not rerun the action |
| Candidate drift or input drift changes any result-affecting binding | Reject the receipt and rerun only the invalidated proof |
| A required binding is absent, unknown, or stale | Treat the action as uncacheable and run it |
| Same proof appears as both cached PASS and a duplicate FOCUS execution | Count it once; the duplicate adds no evidence |

An integrated RC still records one exact final candidate. Commit-only movement does not
magically authorize a stale RC: validate the proof map against the final candidate and
reject result-affecting drift.

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. IDENTIFY: Which action or integrated outcome proves this claim?
2. BIND: Resolve its exact action key and result-affecting input bindings.
3. RESOLVE: Reuse an exact-bound PASS, or rerun only the invalidated proof.
4. READ: Inspect the receipt/output, exit code, and failure count.
5. VERIFY: Does the evidence confirm the claim for this candidate?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
6. ONLY THEN: Make the claim

Skip any step = lying, not verifying
```

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Exact-bound PASS receipt: 0 failures | Unbound previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom: passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle plus exact-bound PASS | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Line-by-line checklist | Tests passing |

## Red Flags - STOP

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!", etc.)
- About to commit/push/PR without verification
- Trusting agent success reports
- Reusing evidence after candidate drift or input drift
- Counting a cached PASS and duplicate FOCUS execution as two proofs
- Thinking "just this once"
- Tired and wanting work over
- **ANY wording implying success without having run verification**

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Just this once" | No exceptions |
| "Linter passed" | Linter ≠ compiler |
| "Agent said success" | Verify independently |
| "I'm tired" | Exhaustion ≠ excuse |
| "The commit changed, so every test must rerun" | Compare result-affecting bindings; commit metadata alone is not an invalidation |
| "The command is the same, so the cache is valid" | Command equality is insufficient; every result-affecting input must match |
| "Running the cached action again gives more confidence" | A duplicate FOCUS execution is the same proof, not independent evidence |
| "Different words so rule doesn't apply" | Spirit over letter |

## Key Patterns

**Tests:**
```
✅ [Resolve exact action key + input bindings] [See exact-bound PASS: 34/34] "All tests pass"
❌ "Should pass now" / "Looks correct"
```

**Regression tests (TDD Red-Green):**
```
✅ Write → Run (pass) → Revert fix → Run (MUST FAIL) → Restore → Run (pass)
❌ "I've written a regression test" (without red-green verification)
```

**Build:**
```
✅ [Run build] [See: exit 0] "Build passes"
❌ "Linter passed" (linter doesn't check compilation)
```

**Requirements:**
```
✅ Re-read plan → Bind proof map → Rerun only invalidated proof → Report gaps or completion
❌ "Tests pass, phase complete"
```

**Agent delegation:**
```
✅ Agent reports success → Check VCS diff → Verify changes → Report actual state
❌ Trust agent report
```

## Why This Matters

From 24 failure memories:
- your human partner said "I don't believe you" - trust broken
- Undefined functions shipped - would crash
- Missing requirements shipped - incomplete features
- Time wasted on false completion → redirect → rework
- Violates: "Honesty is a core value. If you lie, you'll be replaced."

## When To Apply

**ALWAYS before:**
- ANY variation of success/completion claims
- ANY expression of satisfaction
- ANY positive statement about work state
- Committing, PR creation, task completion
- Moving to next task
- Delegating to agents

**Rule applies to:**
- Exact phrases
- Paraphrases and synonyms
- Implications of success
- ANY communication suggesting completion/correctness

## Physical Full-Suite Boundary

A physical full suite is allowed only for one of these explicit triggers:

| Trigger | Meaning |
|---------|---------|
| `bootstrap` | Establish the first instrumented baseline for a registered repository |
| `weekly canary` | Scheduled cache-disabled health check on an isolated exact candidate |
| `named-high-risk:<reason>` | The approved plan names the concrete non-deferable risk |

Normal publish or merge alone is not a full-suite trigger. A physical full run is never
satisfied from cache. Outside those triggers, form one integrated RC from the required
exact-bound receipts and run only invalidated proof.

## The Bottom Line

**No shortcuts for verification.**

Run the command. Read the output. THEN claim the result.

This is non-negotiable.
