---
name: executing-plans
description: Use when an approved implementation plan must be executed by the current native owner into one complete release candidate
---

# Executing Plans

## Overview

Load the approved plan, own the complete release candidate through FOCUS, then prove one exact integrated candidate at RC.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

## Execution Proof Contract

- `FOCUS = the implementation owner's RED → GREEN affected proof loop.`
- `RC = one exact integrated candidate review/proof after all planned outcomes are assembled.`

These are the only execution proof concepts. FOCUS starts from an exact counterexample, makes the smallest implementation change, and reruns the affected proof until GREEN. RC binds the approved spec, plan, candidate identity, and integrated evidence.

A full suite belongs to RC only when the approved plan names a concrete high-risk trigger or the repository release policy explicitly requires it. It does not run by default or inside FOCUS.

## The Process

### Step 1: Load and Review Plan
1. Read the plan file.
2. Review it critically for a genuine missing decision or contradiction.
3. If the approved outcome determines the next action, create todos and proceed.

### Step 2: Execute the Complete Candidate

For each cohesive outcome task:
1. Mark it in progress.
2. Start FOCUS by running its exact counterexample and confirm RED.
3. Implement the smallest change and rerun the affected proof until GREEN.
4. Keep ownership in this session and mark the outcome complete.

Do not insert partial review loops between tasks or run the repository full suite inside FOCUS. Continue until every planned outcome is assembled in one complete release candidate.

### Step 3: Prove the Exact Candidate

After every FOCUS loop is GREEN:
- Bind RC to the exact integrated candidate under review.
- Run one integrated release review/proof against the approved spec, plan, and required integrated evidence.
- If RC finds a defect, reject that candidate, return to the affected FOCUS loop, and form a new exact candidate for RC.
- Invoke `superpowers:finishing-a-development-branch` for final verification and integration choices.

## When to Pause for Input

Pause only for a genuine missing user decision, new authority, or ambiguity that materially changes the approved outcome. A test failure, dependency defect, or ordinary implementation bug is not a reason to stop: diagnose it, return to FOCUS, and resume.

## When to Revisit Earlier Steps

**Return to Review (Step 1) when:**
- Partner updates the plan based on your feedback.
- The fundamental approach needs rethinking.

**Fix and resume** ordinary execution defects; ask only when the approved outcome cannot determine the next action.

## Remember

- Review the approved plan once before implementation.
- Own the complete release candidate.
- Keep each FOCUS loop to its RED → GREEN affected proof.
- Bind RC to one exact integrated candidate and its evidence.
- Run a full suite only for a named high-risk or release-policy trigger.
- Never start implementation on main/master without explicit user consent.

## Integration

- `superpowers:writing-plans` creates the plan this skill executes.
- `superpowers:using-git-worktrees` provides isolation when the current checkout can collide with unrelated work.
- `superpowers:finishing-a-development-branch` completes final verification and integration.
