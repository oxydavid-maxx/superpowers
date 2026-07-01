"""progress_state (2026-07-01, 光佑's fix): the Progress Line must be GENERATED from a
real, on-disk, ground-truth-derived state file -- never composed from the agent's
memory of the conversation. derive_current_gate() inspects the filesystem the same
way spec_audit re-derives final_ready: trust nothing self-declared, recompute from
what actually exists. This closes the exact incident: an agent that writes a plan
file (S3) without ever having produced a test-design.json (S2) must be reported as
"still stuck at S2", regardless of what the agent claims in its own response.
"""
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".claude" / "lib"))
from progress_state import derive_current_gate, refresh_progress, write_golden


def _spec(tmp_path, registry, status="DRAFT"):
    d = tmp_path / ".superpowers" / "spec"
    d.mkdir(parents=True, exist_ok=True)
    (d / "spec.md").write_text(
        f"---\nstatus: {status}\n---\n# Spec\n\n```registry\n{json.dumps(registry)}\n```\n",
        encoding="utf-8",
    )
    return d


def test_empty_repo_is_s0():
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        assert derive_current_gate(Path(td)) == "S0_DISCUSS"


def test_spec_drafted_but_no_mock_is_mock_v1(tmp_path):
    _spec(tmp_path, [{"cap_id": "C-1"}])
    assert derive_current_gate(tmp_path) == "S1_EXPECTED_MOCK_V1"


def test_mock_v1_present_but_no_sota_is_sota(tmp_path):
    d = _spec(tmp_path, [{"cap_id": "C-1"}])
    (d / "mock-iteration.json").write_text(json.dumps({"mock_v1_score": 0.5}), encoding="utf-8")
    assert derive_current_gate(tmp_path) == "S1_SOTA"


def test_reused_sota_source_does_not_count_stays_at_sota(tmp_path):
    # the exact incident: a SOTA record exists but is reused from a prior spec -- ground
    # truth must NOT treat that as real prior-art search.
    d = _spec(tmp_path, [{"cap_id": "C-1"}])
    (d / "mock-iteration.json").write_text(json.dumps({"mock_v1_score": 0.5}), encoding="utf-8")
    (d / "sota-pass2.json").write_text(json.dumps(
        [{"cap_id": "C-1", "sources": [{"name": "old", "url": "https://x", "reused_from_prior_spec": True}]}]
    ), encoding="utf-8")
    assert derive_current_gate(tmp_path) == "S1_SOTA"


def test_the_exact_incident_plan_written_without_verification_plan_stays_at_s2(tmp_path):
    # The real incident, generalized: a plan file exists (agent believes it's at S3/S4),
    # but no verify/test-design.json was ever produced. Ground truth must report S2,
    # not whatever the agent's own progress line claimed.
    _spec(tmp_path, [{"cap_id": "C-1", "type_tags": ["ui"], "entry_point": "p.html",
                      "entry_type": "ui", "reachable_path": "/p", "need_ids": ["N-1"],
                      "acceptance": {"given": "a", "when": "b", "then": "a banner appears on the page"},
                      "state_data_contract": None, "failure_modes": ["a clear error appears"],
                      "gap_questions": []}], status="FINAL")
    d = tmp_path / ".superpowers" / "spec"
    (d / "stakeholder-needs.json").write_text(json.dumps([{"need_id": "N-1"}]), encoding="utf-8")
    (d / "material-unknowns.json").write_text(json.dumps([{"id": "U-1", "status": "resolved"}]), encoding="utf-8")
    (d / "decision-log.md").write_text("decided X because Y", encoding="utf-8")
    (d / "mock-iteration.json").write_text(json.dumps({"mock_v1_score": 0.7, "material_final_spec_change": False, "mock_v2_na_reason": "n/a"}), encoding="utf-8")
    (d / "sota-pass2.json").write_text(json.dumps(
        [{"cap_id": "C-1", "sources": [{"name": "Gmail", "url": "https://gmail.com"}]}]
    ), encoding="utf-8")
    # author skipped straight to writing a plan file -- no .superpowers/verify/test-design.json
    plans = tmp_path / "docs" / "superpowers" / "plans"
    plans.mkdir(parents=True)
    (plans / "2026-07-01-fake-plan.md").write_text("# Plan\n## Recommended executor: subagent-driven\n", encoding="utf-8")
    assert derive_current_gate(tmp_path) == "S2_VERIFICATION_PLAN"


def test_refresh_progress_writes_real_files_and_returns_compact_line(tmp_path):
    result = refresh_progress(tmp_path)
    assert (tmp_path / ".superpowers" / "fsm" / "progress.json").is_file()
    assert (tmp_path / ".superpowers" / "fsm" / "golden.json").is_file()
    progress = json.loads((tmp_path / ".superpowers" / "fsm" / "progress.json").read_text(encoding="utf-8"))
    assert progress["current_gate"] == "S0_DISCUSS"
    assert result["line"].startswith("Superpower: now=S0_DISCUSS(")


def test_golden_file_matches_the_pure_stage_list(tmp_path):
    write_golden(tmp_path)
    golden = json.loads((tmp_path / ".superpowers" / "fsm" / "golden.json").read_text(encoding="utf-8"))
    assert [s["gate"] for s in golden["stages"]] == [
        "S0_DISCUSS", "S1_SPEC_DRAFT", "S1_EXPECTED_MOCK_V1", "S1_SOTA", "S1_REVISE_DISCUSS",
        "S1_SPEC_FINAL", "S1_EXPECTED_MOCK_V2", "S2_VERIFICATION_PLAN", "S3_IMPLEMENTATION_PLAN",
        "S4_BUILD", "S5_VERIFY_ARCH", "S5_VERIFY_SPEC", "S5_FIX_LOOP", "S6_RELEASE",
    ]
