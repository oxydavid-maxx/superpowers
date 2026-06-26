---
name: human-factors
description: Use to set (left arm) and verify (right arm) the usability bar for any entry point. Generic usability fitness-function provider; dispatches to a surface-specific rubric. UI dispatches to skill-ui-human.
---

# human-factors — generic usability rubric

Authored on the LEFT (write the bar into the registry's `human_factors_bar`) and checked on the RIGHT (verify against that bar). One ruler, both arms.

Dispatch by entry-point type:

| entry type | rubric |
|---|---|
| UI | invoke `skill-ui-human` (full depth, unchanged) |
| CLI | cli-dx: help clarity, error messages, exit codes, discoverability |
| API | cognitive-dimensions (Clarke's 12 dimensions) |
| library | lib-dx: API design, types, least-surprise, docs |

RULE: always dispatch to a concrete, verifiable rubric. Never emit a usability platitude ("be usable") — a bar with no observable pass condition is invalid.
