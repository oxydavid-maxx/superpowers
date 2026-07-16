---
name: executing-plans
description: Use when an approved implementation plan must be executed by the current native owner into one complete release candidate
---

# Executing Plans

## Overview

Load the approved plan, own the full implement → focused-test → fix loop, assemble one complete release candidate, then report.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

## The Process

### Step 1: Load and Review Plan
1. Read plan file
2. Review critically - identify any questions or concerns about the plan
3. If concerns: Raise them with your human partner before starting
4. If no concerns: Create todos for the plan items and proceed

### Step 2: Execute the Complete Candidate

For each cohesive outcome task:
1. Mark it in progress.
2. Run its exact T0 counterexample.
3. Implement, run T1, and fix until the focused proof is green.
4. Keep ownership in this session and mark the outcome complete.

Do not open partial review loops between tasks and do not rerun the repository full
suite during fix loops. Continue until every planned outcome is assembled in one
complete release candidate.

### Step 3: Complete Development

After the complete release candidate exists and focused proofs are green:
- Perform one integrated release review against the approved spec and plan.
- Fix findings in the same logical ownership lane and rerun only affected proofs.
- Invoke `superpowers:finishing-a-development-branch` for final verification and integration choices.

## When to Pause for Input

Pause only for a genuine missing user decision, new authority, or ambiguity that
materially changes the approved outcome. A test failure, dependency defect, or ordinary
implementation bug is not a reason to stop: diagnose, fix, and resume from the failed
focused stage.

## When to Revisit Earlier Steps

**Return to Review (Step 1) when:**
- Partner updates the plan based on your feedback
- Fundamental approach needs rethinking

**Fix and resume** ordinary execution defects; ask only when the approved outcome cannot determine the next action.

## Remember
- Review the approved plan once before implementation.
- Own the complete release candidate, not a mechanical tail.
- Keep fix loops at T0/T1; do not repeat a stable T2 or full suite.
- Run one integrated release review after assembly.
- Never start implementation on main/master without explicit user consent.

## Integration

- `superpowers:writing-plans` creates the plan this skill executes.
- `superpowers:using-git-worktrees` provides isolation when the current checkout can collide with unrelated work.
- `superpowers:finishing-a-development-branch` completes final verification and integration.
