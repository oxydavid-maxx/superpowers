---
name: brainstorming
description: "You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements and design before implementation."
---

# Brainstorming Ideas Into Designs

Help turn ideas into fully formed designs and specs through natural collaborative dialogue.

Start by understanding the current project context, then ask questions one at a time to refine the idea. Once you understand what you're building, present the design and get user approval.

<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it. This applies to EVERY project regardless of perceived simplicity.
</HARD-GATE>

## Anti-Pattern: "This Is Too Simple To Need A Design"

Every project goes through this process. A todo list, a single-function utility, a config change — all of them. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be short (a few sentences for truly simple projects), but you MUST present it and get approval.

## Checklist

Before asking ANY question: read the relevant files/configs/commits first. Never spend a question on a fact you can obtain yourself (investigate-before-ask).

Before you may "Propose approaches" you MUST pass a context-completeness check: explicitly list the remaining MATERIAL unknowns about intent / constraints / context. If that list is non-empty, keep asking — there is NO fixed question count (three is not a target). The bar is ZERO material unknowns before you propose.

You MUST create a task for each of these items and complete them in order:

1. **Explore project context** — check files, docs, recent commits
2. **Offer the visual companion just-in-time** — NOT upfront. The first time a question would genuinely be clearer shown than described, offer it then (its own message); on approval its browser tab opens for you. If no visual question ever arises, never offer it. See the Visual Companion section below.
3. **Ask clarifying questions** — one at a time, understand purpose/constraints/success criteria
4. **Propose 2-3 approaches** — with trade-offs and your recommendation
5. **Present design** — in sections scaled to their complexity, get user approval after each section
6. **Write design doc** — save to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and commit
7. **Spec self-review** — quick inline check for placeholders, contradictions, ambiguity, scope (see below)
8. **User reviews written spec** — ask user to review the spec file before proceeding
9. **Transition to implementation** — read the spec's `## Surfaces`. If ≥2 entry points (multi-entry), invoke **writing-arch** first (author the Interface-Placement Map), then writing-plans. If single-entry, writing-plans directly.

## Process Flow

```dot
digraph brainstorming {
    "Explore project context" [shape=box];
    "Ask clarifying questions" [shape=box];
    "Propose 2-3 approaches" [shape=box];
    "Present design sections" [shape=box];
    "User approves design?" [shape=diamond];
    "Write design doc" [shape=box];
    "Spec self-review\n(fix inline)" [shape=box];
    "User reviews spec?" [shape=diamond];
    "Surfaces >= 2?" [shape=diamond];
    "Invoke writing-arch skill" [shape=doublecircle];
    "Invoke writing-plans skill" [shape=doublecircle];

    "Explore project context" -> "Ask clarifying questions";
    "Ask clarifying questions" -> "Propose 2-3 approaches";
    "Propose 2-3 approaches" -> "Present design sections";
    "Present design sections" -> "User approves design?";
    "User approves design?" -> "Present design sections" [label="no, revise"];
    "User approves design?" -> "Write design doc" [label="yes"];
    "Write design doc" -> "Spec self-review\n(fix inline)";
    "Spec self-review\n(fix inline)" -> "User reviews spec?";
    "User reviews spec?" -> "Write design doc" [label="changes requested"];
    "User reviews spec?" -> "Surfaces >= 2?" [label="approved"];
    "Surfaces >= 2?" -> "Invoke writing-arch skill" [label="yes (multi-entry)"];
    "Surfaces >= 2?" -> "Invoke writing-plans skill" [label="no (single-entry)"];
    "Invoke writing-arch skill" -> "Invoke writing-plans skill";
}
```

**The terminal state is writing-arch (multi-entry specs) or writing-plans (single-entry).** Do NOT invoke frontend-design, mcp-builder, or any other implementation skill. After brainstorming, the next skill is **writing-arch** if the spec declares ≥2 Surfaces, else **writing-plans** — see "Surface routing after spec" below.

## The Process

**Understanding the idea:**

- Check out the current project state first (files, docs, recent commits)
- Before asking detailed questions, assess scope: if the request describes multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), flag this immediately. Don't spend questions refining details of a project that needs to be decomposed first.
- If the project is too large for a single spec, help the user decompose into sub-projects: what are the independent pieces, how do they relate, what order should they be built? Then brainstorm the first sub-project through the normal design flow. Each sub-project gets its own spec → plan → implementation cycle.
- For appropriately-scoped projects, ask questions one at a time to refine the idea
- Prefer multiple choice questions when possible, but open-ended is fine too
- Only one question per message - if a topic needs more exploration, break it into multiple questions
- Focus on understanding: purpose, constraints, success criteria

**Exploring approaches:**

- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why

**Presenting the design:**

- Once you believe you understand what you're building, present the design
- Scale each section to its complexity: a few sentences if straightforward, up to 200-300 words if nuanced
- Ask after each section whether it looks right so far
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify if something doesn't make sense

**Design for isolation and clarity:**

- Break the system into smaller units that each have one clear purpose, communicate through well-defined interfaces, and can be understood and tested independently
- For each unit, you should be able to answer: what does it do, how do you use it, and what does it depend on?
- Can someone understand what a unit does without reading its internals? Can you change the internals without breaking consumers? If not, the boundaries need work.
- Smaller, well-bounded units are also easier for you to work with - you reason better about code you can hold in context at once, and your edits are more reliable when files are focused. When a file grows large, that's often a signal that it's doing too much.

**Working in existing codebases:**

- Explore the current structure before proposing changes. Follow existing patterns.
- Where existing code has problems that affect the work (e.g., a file that's grown too large, unclear boundaries, tangled responsibilities), include targeted improvements as part of the design - the way a good developer improves code they're working in.
- Don't propose unrelated refactoring. Stay focused on what serves the current goal.

## After the Design

**Documentation:**

- Write the validated design (spec) to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
  - (User preferences for spec location override this default)
- Use elements-of-style:writing-clearly-and-concisely skill if available
- Commit the design document to git

**Spec Self-Review:**
After writing the spec document, look at it with fresh eyes:

1. **Placeholder scan:** Any "TBD", "TODO", incomplete sections, or vague requirements? Fix them.
2. **Internal consistency:** Do any sections contradict each other? Does the architecture match the feature descriptions?
3. **Scope check:** Is this focused enough for a single implementation plan, or does it need decomposition?
4. **Ambiguity check:** Could any requirement be interpreted two different ways? If so, pick one and make it explicit.

Fix any issues inline. No need to re-review — just fix and move on.

**User Review Gate:**
After the spec review loop passes, ask the user to review the written spec before proceeding:

> "Spec written and committed to `<path>`. Please review it and let me know if you want to make any changes before we start writing out the implementation plan."

Wait for the user's response. If they request changes, make them and re-run the spec review loop. Only proceed once the user approves.

**Implementation:**

- Read the spec's `## Surfaces` section. If it lists ≥2 entry points (multi-entry), invoke the **writing-arch** skill first to author the Interface-Placement Map, THEN writing-plans. If single-entry, invoke writing-plans directly.
- Do NOT invoke unrelated implementation skills (frontend-design, mcp-builder, etc.).

## Key Principles

- **One question at a time** - Don't overwhelm with multiple questions
- **Multiple choice preferred** - Easier to answer than open-ended when possible
- **YAGNI ruthlessly** - Remove unnecessary features from all designs
- **Explore alternatives** - Always propose 2-3 approaches before settling
- **Incremental validation** - Present design, get approval before moving on
- **Be flexible** - Go back and clarify when something doesn't make sense

## Visual Companion

A browser-based companion for showing mockups, diagrams, and visual options during brainstorming. Available as a tool — not a mode. Accepting the companion means it's available for questions that benefit from visual treatment; it does NOT mean every question goes through the browser.

**Offering the companion (just-in-time):** Do NOT offer it upfront. Wait until a question would genuinely be clearer shown than told — a real mockup / layout / diagram question, not merely a UI *topic*. The first time that happens, offer it then, as its own message:
> "This next part might be easier if I show you — I can put together mockups, diagrams, and comparisons in a browser tab as we go. It's still new and can be token-intensive. Want me to? I'll open it for you."

**This offer MUST be its own message.** Only the offer — no clarifying question, summary, or other content. Wait for the user's response. If they accept, start the server with `--open` so their browser opens to the first screen automatically. If they decline, continue text-only and don't offer again unless they raise it.

**Per-question decision:** Even after the user accepts, decide FOR EACH QUESTION whether to use the browser or the terminal. The test: **would the user understand this better by seeing it than reading it?**

- **Use the browser** for content that IS visual — mockups, wireframes, layout comparisons, architecture diagrams, side-by-side visual designs
- **Use the terminal** for content that is text — requirements questions, conceptual choices, tradeoff lists, A/B/C/D text options, scope decisions

A question about a UI topic is not automatically a visual question. "What does personality mean in this context?" is a conceptual question — use the terminal. "Which wizard layout works better?" is a visual question — use the browser.

If they agree to the companion, read the detailed guide before proceeding:
`skills/brainstorming/visual-companion.md`

## Required spec sections (V-model)

Every spec you write MUST include, as first-class sections:

1. **Capability Registry** — one row per designed capability: `Cap-ID | capability (user outcome) | entry_point | entry_type (UI/CLI/API/library) | reachable_path | acceptance_example`. This is the deterministic referent the right-arm verify-arch / verify-spec check the assembled product against.
2. **`## Surfaces`** — one row per user-reachable entry point: `- <name>: <UI|CLI|API|library> — <description>`. The COUNT of rows decides routing: ≥2 → multi-entry → writing-arch required. A capability named in prose but absent from the Registry/Surfaces is a defect (prose↔registry lint). For a redesign, declare `supersedes` so baseline reconciliation flags silently-dropped capabilities.
3. **Prior art / alternatives considered + verdicts** — SOTA falsification: each finding gets adopt / adapt / reject + a one-line reason and a citation. Authored after intent is clear, before the spec is final.

## Surface routing after spec (the architecture phase — LEFT arm of the V)

After the spec is approved, route by the `## Surfaces` count:

- **Multi-entry (Surfaces ≥ 2):** invoke **writing-arch** to author the Interface-Placement Map (which capability lives on which entry point, the reachable path, cross-surface links). Skipping it leaves verify-arch with no referent — the documented "capability assembled onto the wrong surface" failure. THEN invoke writing-plans.
- **Single-entry (Surfaces = 1):** invoke writing-plans directly.

This is the primary post-spec routing. The DOT graph and the imperatives above all reflect it.

## Visual mock after spec (whenever the spec has a Capability Registry)

After the spec is approved and BEFORE handing off to writing-arch / writing-plans, produce a NON-INTERACTIVE visual mock so the user can SEE the rough shape — but ONLY when the spec has UI surfaces (skip for pure CLI/API/library specs, where a clickable mock is meaningless):

1. Generate: `py -3 ~/.claude/lib/mock_visual.py <spec.md> <outdir>/site --title "<project> (spec mock)"` (reads the Capability Registry; one clickable page per UI entry point).
2. Serve: `bash ~/.claude/lib/serve-tunnel.sh <outdir>/site` — it prints PUBLIC_URL.
3. Give the user the PUBLIC_URL; say it is NON-INTERACTIVE (just the look/layout) — click through the surfaces.
