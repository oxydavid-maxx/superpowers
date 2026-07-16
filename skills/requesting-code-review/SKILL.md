---
name: requesting-code-review
description: Use when an exact integrated candidate is ready for RC review/proof, before merge or release, or when an additional review is explicitly requested
---

# Requesting Code Review

## Overview

The current native owner reviews one exact integrated candidate against the approved requirements and its proof receipts. Do not insert a separate review layer between FOCUS loops.

**Core principle:** Bind every finding and verdict to the exact candidate under review.

## When to Review

- After all planned outcomes are assembled and the candidate is ready for RC.
- Before merge or release when repository policy requires that review.
- When the user explicitly requests an additional review.

Do not make review mandatory after each task. During implementation, the owner stays in FOCUS and reruns only the affected proof until GREEN.

## Review Procedure

### 1. Bind the candidate

Record the exact base and head commit IDs, or an equivalent immutable diff identity. Never infer the base from `HEAD~1` when the candidate may contain multiple commits.

### 2. Load the authority

Review only against:
- the approved specification and implementation plan;
- the exact candidate diff;
- the affected proof receipts and required integrated evidence;
- any named high-risk or release-policy trigger.

### 3. Inspect the candidate

Check requirement coverage, correctness, error handling, regression risk, security or data-safety impact, maintainability, and whether the proof receipts support the claimed outcome.

### 4. Record evidence-backed findings

Classify findings as Critical, Important, or Minor. Every finding names the file and line when available, explains the concrete failure mode, and cites the requirement or evidence it violates.

### 5. Resolve the verdict

- Critical or Important findings reject the candidate. Return to the affected FOCUS loop, reach GREEN, and form a new exact candidate for RC.
- Minor findings may be fixed now or recorded explicitly when they do not affect acceptance.
- If a finding is technically wrong, reject it with code, test, or requirement evidence.

## Full-Suite Boundary

A full suite runs only when the approved plan names a concrete high-risk trigger or repository release policy explicitly requires it. Otherwise review uses the exact integrated proofs required for this candidate.

## Optional Independent Review

If the user or repository policy explicitly requires an independent reviewer, use [code-reviewer.md](code-reviewer.md) as the evidence template. This is optional collaboration, not the default execution owner.

## Integration with Workflows

- **Executing Plans:** RC performs one review/proof after the complete candidate is assembled.
- **Legacy explicit-request workflow:** `subagent-driven-development` may use the template inside its opt-in mechanics.
- **Ad-hoc development:** bind the exact candidate before review rather than reviewing a moving worktree.

## Red Flags

- Reviewing a moving or unidentified candidate.
- Adding task-by-task review by default.
- Running a full suite without a named trigger.
- Reporting findings without file, requirement, or proof evidence.
- Ignoring valid Critical or Important findings.
