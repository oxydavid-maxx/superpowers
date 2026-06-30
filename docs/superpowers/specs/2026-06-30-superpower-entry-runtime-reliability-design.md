# Superpower Entry + Runtime Reliability

Status: FINAL-PENDING-USER-REVIEW
Date: 2026-06-30

## Problem

Superpower can be installed and documented correctly but still fail in live sessions when agents skip stages, hard-pin stale skill versions, print inert boilerplate, or treat external builders as an always-on role. The fix is to make the entry behavior, version pointer model, stage order, skill mapping, and feedback loop machine-checkable while keeping the first user-facing response concise and useful.

## Scope

This spec covers the Superpower fork runtime behavior for Claude and Codex sessions:

- Superpower entry response and comprehension gate.
- Complete stage order with required skill mapping.
- Stable `current` pointer install model for Claude and Codex.
- Removal/prevention of hard-pinned Superpower skill paths in active registries.
- S4_BUILD executor outsourcing rule.
- Verification-plan category growth via feedback loop and house-cleaning.
- Finish gates that prevent incomplete claims.

This spec does not implement `skill-orch-x-ai`; it only makes Superpower standalone-compatible and future external-builder-compatible.

## Stakeholders And Needs

| Need-ID | Stakeholder | Need | Acceptance signal |
|---|---|---|---|
| N-01 | User | Calling Superpower reliably starts the same process every time. | First response states complete stage order, current state, current action, and skill mapping. |
| N-02 | Current session | The active session knows which work is allowed now. | Entry response says S0_DISCUSS only; no spec/plan/code before the gate. |
| N-03 | Future sessions | New sessions load the latest Superpower without manual path updates. | Claude and Codex discover Superpower through `current`, not versioned hard-pins. |
| N-04 | External builder session | A delegated builder receives only S4_BUILD work. | Job schema rejects spec/verification/release file changes from builder. |
| N-05 | Verifier | Verification plans grow from observed misses. | Verification gaps become structured lessons/checklist entries. |
| N-06 | Maintainer | Low-risk drift is auto-cleaned without hiding important decisions. | House-cleaning can apply low-risk lint fixes; unresolved P2/P3 still block signoff. |

## Capability Registry

| Cap-ID | need_ids | capability (user outcome) | entry_point | entry_type | type_tags | reachable_path | acceptance_example |
|---|---|---|---|---|---|---|---|
| SPR-ENTRY-01 | N-01,N-02 | When the user invokes Superpower, the session gives a natural-language complete stage-order recap before task work. | superpower-skill-entry | process | process,gate | `skills/using-superpowers/SKILL.md` | Given a prompt saying "use superpower", when the session responds, then it names S0 through S6, maps each stage to skills, states current state/action, and does not only paste fixed boilerplate. |
| SPR-ENTRY-02 | N-02 | The first Superpower state is S0_DISCUSS and blocks premature spec/plan/code. | superpower-skill-entry | process | process,gate | `skills/using-superpowers/SKILL.md`, `skills/brainstorming/SKILL.md` | Given Superpower was invoked, when no S0 discussion has resolved material unknowns, then no implementation plan or code edit is allowed. |
| SPR-SKILLMAP-03 | N-01 | The complete stage order includes the skill(s) each stage must invoke. | superpower-skill-entry | process | process,traceability | `skills/using-superpowers/SKILL.md` | Given the entry recap, then every stage from S0_DISCUSS to S6_RELEASE has a named Superpower skill or explicit conditional skill. |
| SPR-CURRENT-04 | N-03 | Claude and Codex active installs resolve through stable `current` pointers. | install-runtime | CLI | install,distribution | `scripts/pin-local-fork-install.ps1` | Given vmodel.N+1 is released, when pin runs, then Claude and Codex active install metadata point to `.../superpowers/current`, and `current` resolves to vmodel.N+1. |
| SPR-NOHARDPIN-05 | N-03 | Active registries reject Superpower hard-pins to versioned cache paths. | install-runtime | CLI | lint,distribution | `scripts/verify-local-fork-install.ps1` | Given `skills/registry.yaml` contains `superpowers/6.0.3-vmodel.*`, when verifier runs, then it fails and reports the hard-pin line. |
| SPR-BUILD-06 | N-04 | Only S4_BUILD executor may be external, and only after explicit confirmation. | superpower-skill-entry | process | orchestration,gate | `skills/using-superpowers/SKILL.md`, `.superpowers/orch/jobs/*.json` | Given a task is before S4_BUILD, when the agent discusses outsourcing, then it may only refer to `S4_BUILD executor`; other stages stay `current session`. |
| SPR-FEEDBACK-07 | N-05,N-06 | Verification misses feed back into checklist/archetype growth. | verification-runtime | CLI | verification,feedback | `.superpowers/verify/`, house-cleaning routine | Given a verifier finds a missing scenario/category, when the task finishes, then a structured lesson/checklist proposal is recorded and unresolved P2/P3 blocks signoff. |
| SPR-FINISH-08 | N-01,N-05 | Completion claims require evidence from the declared gates. | verification-runtime | CLI | gate,release | `verification-before-completion`, `verify-spec`, `verify-arch` | Given evidence is missing for required gates, when the session tries to claim production-ready, then the gate blocks or forces BLOCKED/PARTIAL wording. |

## Surfaces

- superpower-skill-entry: process - the skill instructions loaded when a user invokes Superpower.
- install-runtime: CLI - pin and verify scripts that install or validate active Superpower copies.
- verification-runtime: CLI - verification plan, finish gate, and house-cleaning feedback artifacts.

## Required Stage Order And Skill Mapping

The entry response must use natural language and include this complete stage order with skill mapping:

| Stage | Skill mapping |
|---|---|
| S0_DISCUSS | `superpowers:brainstorming` |
| S1_SPEC_DRAFT | `superpowers:brainstorming` |
| S1_EXPECTED_MOCK_V1 | `superpowers:brainstorming` |
| S1_SOTA | `superpowers:brainstorming` + WebSearch / source research |
| S1_SPEC_FINAL | `superpowers:brainstorming` |
| S1_EXPECTED_MOCK_V2 | `superpowers:brainstorming` |
| S2_VERIFICATION_PLAN | `superpowers:writing-verification-plans` |
| S3_IMPLEMENTATION_PLAN | `superpowers:writing-plans` |
| S4_BUILD | `superpowers:executing-plans` / `superpowers:test-driven-development` / `superpowers:subagent-driven-development` as applicable |
| S5_VERIFY_ARCH | `superpowers:verify-arch`, only for multi-entry projects |
| S5_VERIFY_SPEC | `superpowers:verify-spec` |
| S5_FIX_LOOP | `superpowers:systematic-debugging` + repeat S4/S5 |
| S6_RELEASE | `superpowers:verification-before-completion` + `superpowers:finishing-a-development-branch` |

The response must also state:

- Current state is `S0_DISCUSS`.
- Current action is requirements clarification only.
- Owner is `current session`.
- `S4_BUILD executor` defaults to `current session`.
- Only `S4_BUILD executor` can become external, and only after explicit confirmation before S4_BUILD.
- Runtime names such as Codex or Claude are not default role names.

## Feedback Loop

Verification gaps are first-class inputs, not ad hoc notes. The loop is:

1. Verifier records a missing verification category, scenario archetype, or evidence requirement as structured feedback.
2. House-cleaning classifies it as low-risk lint, checklist growth, archetype growth, or policy change.
3. Low-risk lint may be auto-applied.
4. Checklist/archetype/policy changes require durable proposal records and tests.
5. Unresolved P2/P3 feedback blocks signoff; work is not considered complete while known feedback remains unhandled.

## Expected Mock Artifact

Mock v1: `docs/superpowers/mocks/2026-06-30-superpower-entry-runtime-reliability/mock-v1-stage-order.md`

This is a non-UI process mock showing the intended first response shape and stage order.

## Prior Art / SOTA + Verdicts

| Finding | Source | Verdict | Reason |
|---|---|---|---|
| Stable active pointer over immutable releases is an established deployment pattern. | Capistrano Structure docs (https://capistranorb.com/documentation/getting-started/structure/) document `current -> releases/<timestamp>` and update-at-success behavior; Homebrew Formula Cookbook (https://docs.brew.sh/Formula-Cookbook) documents `opt` as a symlink to the active keg version. | adopt | This matches the requested hardware-style `current` pointer and reduces registry blast radius. |
| Versioned installs should still be auditable. | Homebrew Formula Cookbook (https://docs.brew.sh/Formula-Cookbook) uses versioned kegs plus metadata/audit concepts; Capistrano Structure docs (https://capistranorb.com/documentation/getting-started/structure/) keep timestamped releases and revision logs. | adapt | Keep immutable `6.0.3-vmodel.N` caches plus `.superpowers-active.json`; active discovery points at `current`. |
| LLM process compliance needs programmable/explicit rails, not only prose reminders. | NVIDIA NeMo Guardrails docs (https://docs.nvidia.com/nemo/guardrails/latest/) document configurable guardrails, flows, evaluation, tracing, and metrics; this supports explicit rails over prose-only reminders. | adapt | Entry recap is a comprehension gate; tool/file gates and verifier checks must enforce stage order where possible. |
| Fixed boilerplate is insufficient evidence of comprehension. | NVIDIA NeMo Guardrails docs (https://docs.nvidia.com/nemo/guardrails/latest/) distinguish explicit guardrail flows/evaluation from normal model behavior. | adopt | Require natural-language complete stage-order recap with skill mapping; reject boilerplate-only responses. |
| Feedback loops are a standard quality mechanism. | Continuous improvement practice frames feedback as process input; detected verification misses must become checklist/archetype changes rather than one-off notes. | adopt | Verification misses become structured checklist/archetype proposals handled by house-cleaning; unresolved P2/P3 blocks signoff. |
| LangGraph-style orchestration is not required for this fix. | Workflow/guardrail systems support explicit flows, but this change mainly needs local stage state, skill text, hooks/lints, and release verification. | reject for now | Adding a graph runtime would increase surface area before the simpler gates are exhausted. |

SOTA conclusion: keep the design. Implement stable `current` pointers, natural-language complete stage-order recaps, hard-pin verifiers, S4-only external execution, and feedback-loop growth. Do not add LangGraph in this iteration.

## Open Material Unknowns

None currently known from the stakeholder discussion. Any new unknown discovered during SOTA must return to S0/S1 discussion before finalizing.


