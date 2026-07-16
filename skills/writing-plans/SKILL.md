---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give the current owner the whole plan as cohesive outcome tasks that converge into one complete release candidate. Express its execution proof flow only as FOCUS and RC. DRY. YAGNI. TDD. One candidate commit per coherent repository diff.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** If working in an isolated worktree, it should have been created via the `superpowers:using-git-worktrees` skill at execution time.

**Save plans to:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

**Rendered review page required:** Any implementation plan Markdown intended for user review MUST also be rendered to a clickable HTML review page with `source-sha256` metadata. When handing off for approval, provide both the raw plan path and the rendered page link. Raw Markdown alone is not valid human-review evidence.

## Execution Proof Contract

- `FOCUS = the implementation owner's RED → GREEN affected proof loop.`
- `RC = one exact integrated candidate review/proof after all planned outcomes are assembled.`

These are the only execution proof concepts a plan introduces. Each FOCUS names its exact RED counterexample and the affected proof that must become GREEN. RC binds the approved requirements, exact candidate identity, and integrated evidence.

A full suite belongs to RC only when the plan names a concrete high-risk trigger or the repository release policy explicitly requires it; otherwise RC uses only the exact integrated proofs required by the plan.

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Task Right-Sizing

A task is a cohesive outcome slice with its own FOCUS. Fold setup, configuration, scaffolding, migrations, and documentation into the outcome that needs them. Task boundaries follow product outcomes, not assignment or reviewer mechanics. The complete release candidate receives one integrated release review/proof at RC after all planned outcomes are assembled.

## Cohesive Task Granularity

Plan steps must be concrete and executable, but they do not need to fit an artificial
2–5 minute budget. Each task names the RED counterexample, the smallest implementation loop,
the affected proof that must reach GREEN, and the candidate boundary. Avoid per-file or per-test tickets
when one owner can self-converge the whole outcome more cheaply.

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **Execution:** The current native owner implements the complete release candidate, owns every FOCUS loop, and produces the exact candidate for RC. The plan does not mandate delegation or a separate reviewer. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

## Global Constraints

[The spec's project-wide requirements — version floors, dependency limits,
naming and copy rules, platform requirements — one line each, with exact
values copied verbatim from the spec. Every task's requirements implicitly
include this section.]

---
```

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Interfaces:**
- Consumes: [what this task uses from earlier tasks — exact signatures]
- Produces: [what later tasks rely on — exact function names, parameter
  and return types. A task's implementer sees only their own task; this
  block is how they learn the names and types neighboring tasks use.]

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

## Remember
- Exact file paths always
- Complete code in every step — if a step changes code, show the code
- Exact commands with expected output
- DRY, YAGNI, TDD, frequent commits

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. Run this as one inline plan-coverage pass before handing the plan to implementation.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.

**3. Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

**4. Product-coverage boundary:** This Self-Review checks **plan-coverage** only (does a task implement each spec requirement). **Product-coverage** — does the assembled, running product deliver each capability on its declared entry point — is owned by the right-arm verify-arch / verify-spec against the Interface-Placement Map, not claimed here.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Execution Handoff

The current native owner executes the complete release candidate and owns every FOCUS loop and RC. The plan never selects a model, thread, worker identity, or executor tool, and it never mandates delegation or a separate review layer.

Each task supplies the exact RED counterexample and affected proof that must reach GREEN. After assembly, RC performs one integrated release review/proof against the exact integrated candidate and approved requirements.

Include a full suite only when Global Constraints names a concrete high-risk trigger or repository release policy explicitly requires it. Otherwise RC uses the exact integrated proofs named by the plan. If RC finds a defect, reject that candidate, return to the corresponding FOCUS loop, and produce a new exact candidate.

## SPG Lifecycle Authority

When this plan runs under SPG, only `S0_APPROVE` and `S1_APPROVE` are human approval
gates. `S2`–`S6`, including `S3_IMPLEMENTATION_PLAN`, are mechanical evidence gates:
do not request or consume `plan_approval`, `executor_confirm`, or any other human token
for S3 planning.

## Plan Coverage Gate

Before S4_BUILD begins, a `plan-coverage.json` artifact must exist reporting zero spec-capability gaps. The orchestrator runs the coverage check; the builder must not start without the green artifact.

## Superpower Progress Line

When this skill is used as part of Superpower, emit the compact progress line only on S3 entry and S3 exit (when handing off to S4_BUILD), not on every internal action.

`Superpower: now=S3_IMPLEMENTATION_PLAN(superpowers:writing-plans); next=S4_BUILD(current host session, host-native) > ...`

Already-passed gates are omitted. Do not print this line for routine tool calls or internal progress inside S3.
