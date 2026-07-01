import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "payload"))

from superpower_fsm import (
    compact_progress,
    validate_owner_boundary,
    validate_gate_prerequisites,
    validate_builder_job,
)


def test_entry_line_contains_full_remaining_flow():
    line = compact_progress("S0_DISCUSS", "superpowers:brainstorming")
    assert line.startswith("Superpower: now=S0_DISCUSS(superpowers:brainstorming); next=")
    assert "S1_EXPECTED_MOCK_V1(superpowers:brainstorming)" in line
    assert "S2_VERIFICATION_PLAN(superpowers:writing-verification-plans)" in line
    assert "S5_VERIFY_ARCH(superpowers:verify-arch, if multi-entry)" in line
    assert "S5_FIX_LOOP(superpowers:systematic-debugging, if failed)" in line


def test_mid_flow_removes_completed_gates():
    line = compact_progress("S2_VERIFICATION_PLAN", "superpowers:writing-verification-plans")
    assert "S0_DISCUSS" not in line
    assert "S1_SPEC_DRAFT" not in line
    assert "S3_IMPLEMENTATION_PLAN(superpowers:writing-plans)" in line


def test_delegated_owner_is_explicit():
    line = compact_progress(
        "S4_BUILD",
        "superpowers:executing-plans",
        owner="Claude:home-superpower",
        owner_by_gate={"S4_BUILD": "Claude:home-superpower"},
    )
    assert "now=S4_BUILD(superpowers:executing-plans @Claude:home-superpower)" in line


def test_external_builder_allowed_only_for_s4_build():
    assert validate_owner_boundary("S4_BUILD", "Claude:home-superpower") == []


def test_external_builder_cannot_own_spec_or_verification_or_release():
    restricted = [
        "S1_SPEC_DRAFT",
        "S2_VERIFICATION_PLAN",
        "S3_IMPLEMENTATION_PLAN",
        "S5_VERIFY_SPEC",
        "S6_RELEASE",
    ]
    for gate in restricted:
        defects = validate_owner_boundary(gate, "Claude:home-superpower")
        assert defects, f"expected defect for gate {gate}"
        assert "external builder may own only S4_BUILD" in defects[0], gate


def test_s3_requires_verification_plan_and_test_design():
    defects = validate_gate_prerequisites("S3_IMPLEMENTATION_PLAN", {"spec_approved": True})
    assert "S3_IMPLEMENTATION_PLAN requires verification_plan and test_design artifacts" in defects
    assert validate_gate_prerequisites(
        "S3_IMPLEMENTATION_PLAN",
        {"spec_approved": True, "verification_plan": True, "test_design": True},
    ) == []


def test_s4_requires_approved_plan_and_locked_s2_artifacts():
    defects = validate_gate_prerequisites(
        "S4_BUILD",
        {
            "spec_approved": True,
            "verification_plan": True,
            "test_design": True,
            "implementation_plan_approved": True,
            "test_design_clean": False,
        },
    )
    assert "S4_BUILD requires locked/clean S2 test-design artifacts" in defects


def test_builder_job_schema_rejects_non_s4_or_release_scope():
    assert validate_builder_job(
        {
            "stage": "S4_BUILD",
            "builder_session": {
                "type": "claude_web",
                "session_name": "home-superpower",
                "user_specified": True,
                "handoff_channel": "chrome",
            },
            "touched_paths": ["lib/runtime/payload/x.py"],
        }
    ) == []

    defects = validate_builder_job({"stage": "S2_VERIFICATION_PLAN", "touched_paths": []})
    assert "builder job stage must be S4_BUILD" in defects

    defects = validate_builder_job(
        {
            "stage": "S4_BUILD",
            "builder_session": {
                "type": "claude_web",
                "session_name": "home-superpower",
                "user_specified": True,
                "handoff_channel": "chrome",
            },
            "touched_paths": ["docs/superpowers/specs/x.md"],
        }
    )
    assert "builder job cannot touch orchestration/spec/verification/release paths" in defects


def test_s4_builder_job_requires_user_specified_claude_web_session():
    missing = validate_builder_job({"stage": "S4_BUILD", "touched_paths": ["lib/runtime/payload/x.py"]})
    assert "builder job requires user-specified Claude web session" in missing

    cli = validate_builder_job(
        {
            "stage": "S4_BUILD",
            "builder_session": {
                "type": "claude_cli",
                "session_name": "home-superpower",
                "user_specified": True,
                "handoff_channel": "cli",
            },
            "touched_paths": ["lib/runtime/payload/x.py"],
        }
    )
    assert "builder_session.type must be claude_web" in cli
    assert "builder_session.handoff_channel must be chrome" in cli

    not_user_specified = validate_builder_job(
        {
            "stage": "S4_BUILD",
            "builder_session": {
                "type": "claude_web",
                "session_name": "home-superpower",
                "user_specified": False,
                "handoff_channel": "chrome",
            },
            "touched_paths": ["lib/runtime/payload/x.py"],
        }
    )
    assert "builder_session.user_specified must be true" in not_user_specified


def test_last_gate_returns_done():
    line = compact_progress("S6_RELEASE", "superpowers:verification-before-completion")
    assert line.endswith("; next=done")


def test_no_owner_omits_at_symbol():
    line = compact_progress("S0_DISCUSS", "superpowers:brainstorming")
    assert "@" not in line.split(";")[0]


def test_builder_prefix_also_restricted():
    defects = validate_owner_boundary("S1_SPEC_DRAFT", "builder:external-session")
    assert defects
    assert "external builder may own only S4_BUILD" in defects[0]
