---
name: writing-arch
description: Use after brainstorming, before writing-plans, for multi-entry-point specs. Expands the spec's Capability Registry into the Interface-Placement Map (which capability lives on which entry point, reachable path, cross-entry links), and declares what prior spec it supersedes (feeds baseline reconciliation). Left-arm architecture phase of the V.
---

# writing-arch — interface / architecture authoring

Input: the spec's Capability Registry (see `verify-arch/registry-schema.md`).
Output: the Interface-Placement Map — for EACH Cap-ID, lock down:
- entry_point + entry_type (UI/CLI/API/library) — where the user does it
- reachable_path — the user route to it
- depends_on — cross-entry links (e.g. dashboard goal -> its note)
- human_factors_bar — the usability pass condition (UI: via skill-ui-human)

For a redesign, set `supersedes` to the prior spec/registry path so baseline
reconciliation (spec §17.1) can flag any silently-dropped capability.

Surface-agnostic: "entry point", not "page". This map is the referent the
right-arm `verify-arch` checks against. Authored on the LEFT, during design —
never derived from the build.


## VISUAL-MOCK-AFTER-ARCH (pipeline step)

After writing the Interface-Placement Map, REGENERATE an updated NON-INTERACTIVE mock (now reflecting exact entry-point placement, reachable paths and cross-surface links) and serve it:
- `py -3 ~/.claude/lib/mock_visual.py <spec-or-arch-map.md> <outdir>/site-v2 --title "<project> (post-arch mock)"`
- `bash ~/.claude/lib/serve-tunnel.sh <outdir>/site-v2` -- give the user the updated PUBLIC_URL.
Tell the user this is the UPDATED visual reflecting the architecture.
