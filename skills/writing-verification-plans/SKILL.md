---
name: writing-verification-plans
description: Use when a reviewed spec exists and implementation planning must be preceded by a deterministic verification test-design.
---

# Writing Verification Plans

## Overview

Create the verification contract that `verify-arch`, `verify-spec`, and finish gates consume. The output is `.superpowers/verify/test-design.json`.

## When to Use

Use after the spec is FINAL/reviewed and before `writing-plans`. Do not use after implementation starts. The verification plan belongs to the orchestrator/verifier, not the builder.

## Inputs

- The spec's Capability Registry.
- The spec's `## Surfaces`.
- Approved visual/mock artifacts when required by `brainstorming`.
- `skill-ui-human` availability when any Cap-ID has `entry_type: UI` or UI tags.

## Output Contract

Write `.superpowers/verify/test-design.json` with:

```json
{
  "schema_version": 1,
  "independent": true,
  "verifier": "<agent/session>",
  "builder": "<agent/session or null>",
  "skill_ui_human_available": true,
  "registry": [
    {
      "cap_id": "CAP-01",
      "entry_type": "UI",
      "risk": {"entry_type": "UI", "tags": ["ui"]}
    }
  ],
  "cases": [
    {
      "case_id": "CAP-01-ui-clickthrough",
      "cap_id": "CAP-01",
      "category": "browser-clickthrough",
      "technique": "use-case",
      "given": "...",
      "when": "...",
      "then": "real browser clickthrough reaches the declared user-visible outcome",
      "executor": "playwright",
      "evidence_policy": "automated_regression"
    }
  ]
}
```

Every Cap-ID must include all categories required by `risk_scale.required_categories()`. For UI Cap-IDs that includes `browser-clickthrough`, `responsive-mobile`, `touch-targets`, `keyboard-focus`, `feedback-states`, `runtime-cleanliness`, and `visual-evidence`.

## UI-Human Requirement

If any capability is UI-facing, preflight `C:\dev\skill-ui-human\SKILL.md`. If unavailable, stop with a blocked verification-plan status. Do not invent a weaker local rubric.

UI cases must include:

| Category | Required assertion shape |
|---|---|
| `browser-clickthrough` | Real click/type/navigation flow reaches the declared outcome. |
| `responsive-mobile` | 390px viewport has no horizontal overflow and preserves task completion. |
| `touch-targets` | Interactive targets meet the `skill-ui-human` touch target bar. |
| `keyboard-focus` | Tab order and visible focus are verified. |
| `feedback-states` | Loading, success, error, and empty states are covered where applicable. |
| `runtime-cleanliness` | Console errors and page errors are captured and must be empty. |
| `visual-evidence` | Screenshot/trace artifact is required. |

## Verify-Arch / Verify-Spec Routing

- Single-entry specs record `verify-arch: N/A` and still require `verify-spec`.
- Multi-entry specs require `verify-arch` before `verify-spec`.
- `verify-spec` always runs.

## Builder Boundary

External builders may only own implementation after `writing-plans`. They never own this verification plan, independent review, `verify-arch`, `verify-spec`, release, or push.

