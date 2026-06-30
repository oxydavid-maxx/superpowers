# Superpower maturity feedback-loop — implementation record (2026-06-30)

Phase-3 build for job `2026-06-30-superpower-maturity-feedback-loop`. Closes the loop from
"a verification gap was found in the field" back to "the upstream gates + lint calibration
improve", without adding a new scheduler. All deterministic logic lives in
`lib/runtime/payload/` (shipped to `~/.claude/lib` by the SessionStart runtime sync) and is
covered by `lib/runtime/tests/test_maturity_feedback_loop.py` + `tests/test-vmodel-contracts.ps1`.

## What ships

| Outcome | Where |
|---|---|
| 1. SYS.1 stakeholder-elicitation HARD GATE before Spec Draft | `skills/brainstorming/SKILL.md` step 4a + `lib/runtime/payload/sys1_elicitation.py` (`stakeholder-needs.json`, `material-unknowns.json`, `decision-log.md`; ZERO unresolved material unknowns; every Need-ID traces to a Cap-ID) |
| 2. verification plan emits JSON **and** MD | `skills/writing-verification-plans/SKILL.md`: `.superpowers/verify/test-design.json` (source of truth) + `.superpowers/verify/test-design.md` (projection) |
| 3. deterministic JSON↔MD projection/parity | `lib/runtime/payload/test_design_projection.py` (`project_md`, `parity_defects`) |
| 4. verification-gap feedback loop | `lib/runtime/payload/verification_feedback.py` — append-only sinks + `blocks_signoff` |
| 5. safe auto-apply predicate | `lib/runtime/payload/autoapply_safety.py` (`is_auto_applicable`) |
| 6. house-cleaning = aggregation/calibration routine | §"House-cleaning contract" below (NO new scheduler) |
| 7. falsification tests | `lib/runtime/tests/test_maturity_feedback_loop.py` (17 tests) + PS contracts |
| 8. release model | unchanged: release-through-`current`-pointer; version bumped per the no-same-version-different-content convention |

## Feedback-event sinks (outcome 4)

Two append-only JSONL sinks (status changes are NEW events, never edits — auditable history;
latest status per `gap_id` wins):
- **project-local:** `<repo>/.superpowers/verify/feedback-events.jsonl`
- **global:** `~/.claude/governance/verification-feedback/events.jsonl`

Event shape (`verification_feedback.make_event`): `{schema_version, gap_id, severity(P0|P1|P2|P3),
cap_id, status(open|ack|resolved|wontfix), ts, detail, source}`.

**Blocked is not done.** `verification_feedback.blocks_signoff(events)` returns the `gap_id`s
whose latest status is unresolved (not `resolved`/`wontfix`) at severity P0/P1/P2/P3. Non-empty
⇒ production signoff is BLOCKED. (Consumers wire this into the finish/signoff check.)

## House-cleaning contract (outcome 6 — no new scheduler)

House-cleaning (the EXISTING weekly routine in `~/.claude`, not a new job) is the
aggregation/calibration step of this loop. Its added responsibilities:

1. **Aggregate** the global `~/.claude/governance/verification-feedback/events.jsonl`: group by
   `cap_id`/pattern, surface recurring gap classes, and report unresolved P0–P3 that still block.
2. **Calibrate** lint thresholds/rules from those patterns (e.g. a recurring proxy-oracle gap →
   tighten a `verify_lint` rule).
3. **Auto-apply only the safe ones.** A calibration change may be auto-applied ONLY if
   `autoapply_safety.is_auto_applicable(change)` is true — deterministic + regression-backed +
   rollback-safe + house-cleaning-controlled + `risk == "low"`. Everything else is DRAFTED to the
   house-cleaning inbox for the user to authorize (T2 operating tier: edits to enforcement
   machinery are human-gated). Honors the IRON RULE: auto-fix requires a verified root cause.

WIRED (not a future seam) — review-fix round:
- `~/.claude/hooks/house_cleaning/audit_verification_feedback.py` (`run(ctx)`) reads the global
  sink and emits unresolved-P0-P3 findings, and is REGISTERED in
  `~/.claude/hooks/house_cleaning/report.py:run_and_collect` (the "Verification Gap Feedback"
  section), so the existing weekly routine runs it — no new scheduler. Test:
  `~/.claude/hooks/house_cleaning/tests/test_audit_verification_feedback.py`.
- The signoff CONSUMER is real: `~/.claude/hooks/pretooluse-verify-finish-gate.py:decide()` now
  loads `<repo>/.superpowers/verify/feedback-events.jsonl` and DENIES 收尾 when
  `verification_feedback.blocks_signoff(...)` is non-empty (unresolved P0-P3 → blocked is not
  done). Tests: `~/.claude/lib/tests/test_verify_finish_gate.py::test_finish_blocked_by_unresolved_feedback_gap`
  / `::test_finish_allowed_when_feedback_resolved`.
- `verification_feedback.py` is shipped in this plugin's `lib/runtime/payload` AND present in
  `~/.claude/lib` so the gate + house-cleaning import it (SessionStart sync keeps them in step).

## Release (outcome 8)

Release model unchanged (release-through-`current`-pointer; `pin-local-fork-install.ps1` +
`verify-local-fork-install.ps1`). Because shipped behavior changed (new gate + skills + runtime),
the version is bumped per the project's no-same-version-different-content convention via
`scripts/bump-version.sh`.
