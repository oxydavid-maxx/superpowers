# Mock v1: Superpower Entry Response Shape

This is a non-interactive process mock. It shows the expected first response shape when a user invokes Superpower.

```text
I am using the Superpower process for this task.

Complete stage order and skills:
S0_DISCUSS - superpowers:brainstorming
S1_SPEC_DRAFT - superpowers:brainstorming
S1_EXPECTED_MOCK_V1 - superpowers:brainstorming
S1_SOTA - superpowers:brainstorming + source research
S1_SPEC_FINAL - superpowers:brainstorming
S1_EXPECTED_MOCK_V2 - superpowers:brainstorming
S2_VERIFICATION_PLAN - superpowers:writing-verification-plans
S3_IMPLEMENTATION_PLAN - superpowers:writing-plans
S4_BUILD - superpowers:executing-plans / test-driven-development / subagent-driven-development as applicable
S5_VERIFY_ARCH - superpowers:verify-arch only for multi-entry projects
S5_VERIFY_SPEC - superpowers:verify-spec
S5_FIX_LOOP - superpowers:systematic-debugging, then repeat S4/S5
S6_RELEASE - superpowers:verification-before-completion + finishing-a-development-branch

Current state: S0_DISCUSS.
Current action: clarify requirements only. I cannot write the spec, plan, or code yet.
Owner: current session.
S4_BUILD executor: current session unless explicitly changed before S4_BUILD.

First material question: <one question here>
```

Failure examples:

- Only pasting a fixed banner.
- Omitting skill mapping.
- Calling the owner Codex or Claude by default.
- Asking for external builder before S4_BUILD.
- Jumping directly to spec, plan, or implementation.
