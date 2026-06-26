# Capability Registry / Interface-Placement Map schema

One row per designed capability. Surface-agnostic ("entry point", not "page").

| field | meaning |
|---|---|
| `cap_id` | stable id, e.g. CAP-01 |
| `capability` | user outcome (what), not a component |
| `entry_point` | where the user does it: page / command / endpoint / function |
| `entry_type` | one of: UI, CLI, API, library |
| `reachable_path` | entry -> there (the user route) |
| `acceptance_example` | concrete input -> observable output (Specification by Example) |
| `human_factors_bar` | usability pass condition (UI: via skill-ui-human) |
| `depends_on` | cross-entry links (Cap-IDs) |
| `supersedes` | for a redesign: the prior spec/registry this replaces |

JSON form: `{"supersedes": "<path|null>", "capabilities": [ {cap_id, capability, entry_point, entry_type, reachable_path, acceptance_example, human_factors_bar, depends_on:[...]}, ... ]}`
