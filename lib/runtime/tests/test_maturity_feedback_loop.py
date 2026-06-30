"""Maturity feedback-loop contracts (job 2026-06-30-superpower-maturity-feedback-loop).

Falsification set (outcome 7) — these FAIL on the pre-job tree (modules absent / skill text
silent) and PASS after the build:
  * SYS.1 elicitation gate (missing artifacts / unresolved unknown / untraced Need-ID)
  * test-design.md projection missing
  * JSON<->MD projection mismatch
  * unresolved verification feedback gap must BLOCK signoff
  * unsafe auto-apply candidate must be REJECTED
  * brainstorming skill text must REQUIRE exhaustive stakeholder elicitation
  * writing-verification-plans skill text must REQUIRE the .md projection
"""
import sys
from pathlib import Path

_PAYLOAD = Path(__file__).resolve().parents[1] / "payload"
sys.path.insert(0, str(_PAYLOAD))
_REPO = Path(__file__).resolve().parents[3]

import sys1_elicitation as sys1            # noqa: E402
import test_design_projection as tdp       # noqa: E402
import verification_feedback as vf         # noqa: E402
import autoapply_safety as aas             # noqa: E402


# ---- outcome 1: SYS.1 stakeholder elicitation gate ----
_REG = {"capabilities": [{"cap_id": "CAP-01", "need_ids": ["N-1"]}]}

def test_sys1_blocks_on_missing_artifacts():
    r = sys1.validate(stakeholder_needs=[], material_unknowns=[], decision_log_text="", registry=_REG)
    assert r["ok"] is False and any("stakeholder" in e for e in r["errors"])

def test_sys1_blocks_on_unresolved_unknown():
    r = sys1.validate(stakeholder_needs=[{"need_id": "N-1"}],
                      material_unknowns=[{"id": "U-1", "status": "open"}],
                      decision_log_text="decided X", registry=_REG)
    assert r["ok"] is False and any("unresolved material unknown" in e for e in r["errors"])

def test_sys1_blocks_on_untraced_need():
    r = sys1.validate(stakeholder_needs=[{"need_id": "N-9"}],
                      material_unknowns=[], decision_log_text="d", registry=_REG)
    assert r["ok"] is False and any("N-9" in e for e in r["errors"])

def test_sys1_passes_when_complete():
    r = sys1.validate(stakeholder_needs=[{"need_id": "N-1"}],
                      material_unknowns=[{"id": "U-1", "status": "resolved"}],
                      decision_log_text="decided X because Y", registry=_REG)
    assert r["ok"] is True and r["errors"] == []


# ---- outcomes 2 + 3: test-design.json -> .md projection + parity ----
_TD = {"capabilities": [
    {"cap_id": "CAP-02", "acceptance": {"then": "the row appears on the page"},
     "techniques": ["round_trip", "boundary"]},
    {"cap_id": "CAP-01", "acceptance": {"then": "exit code 0"}, "techniques": ["error_guessing"]},
]}

def test_projection_is_deterministic():
    assert tdp.project_md(_TD) == tdp.project_md(_TD)   # stable
    # cap order in output is sorted, independent of input order
    assert tdp.project_md(_TD).index("CAP-01") < tdp.project_md(_TD).index("CAP-02")

def test_parity_missing_md_is_defect():
    assert tdp.parity_defects(_TD, "") != []
    assert tdp.parity_defects(_TD, None) != []

def test_parity_mismatch_is_defect():
    assert tdp.parity_defects(_TD, tdp.project_md(_TD) + "\nstray line") != []

def test_parity_exact_projection_passes():
    assert tdp.parity_defects(_TD, tdp.project_md(_TD)) == []


# ---- outcome 4: verification gap feedback loop blocks signoff ----
def test_unresolved_gap_blocks_signoff():
    ev = [vf.make_event(gap_id="G-1", severity="P1", cap_id="CAP-01", status="open", ts=1)]
    assert vf.blocks_signoff(ev) == ["G-1"]

def test_resolved_gap_does_not_block():
    ev = [vf.make_event(gap_id="G-1", severity="P1", cap_id="CAP-01", status="open", ts=1),
          vf.make_event(gap_id="G-1", severity="P1", cap_id="CAP-01", status="resolved", ts=2)]
    assert vf.blocks_signoff(ev) == []

def test_all_p_severities_block():
    ev = [vf.make_event(gap_id=f"G-{s}", severity=s, cap_id="C", status="open", ts=1)
          for s in ("P0", "P1", "P2", "P3")]
    assert sorted(vf.blocks_signoff(ev)) == ["G-P0", "G-P1", "G-P2", "G-P3"]

def test_feedback_append_only_roundtrip(tmp_path):
    p = tmp_path / "feedback-events.jsonl"
    vf.append_event(p, vf.make_event(gap_id="G-1", severity="P2", cap_id="C", status="open", ts=1))
    vf.append_event(p, vf.make_event(gap_id="G-2", severity="P3", cap_id="C", status="open", ts=2))
    evs = vf.load_events(p)
    assert [e["gap_id"] for e in evs] == ["G-1", "G-2"]   # append-only, in order


# ---- outcome 5: auto-apply safety predicate ----
def test_autoapply_rejects_unsafe():
    ok, reasons = aas.is_auto_applicable({"deterministic": True, "regression_backed": True,
                                          "rollback_safe": False, "house_cleaning_controlled": True,
                                          "risk": "low"})
    assert ok is False and any("rollback_safe" in r for r in reasons)

def test_autoapply_rejects_non_low_risk():
    ok, reasons = aas.is_auto_applicable({"deterministic": True, "regression_backed": True,
                                          "rollback_safe": True, "house_cleaning_controlled": True,
                                          "risk": "medium"})
    assert ok is False

def test_autoapply_accepts_fully_safe():
    ok, reasons = aas.is_auto_applicable({"deterministic": True, "regression_backed": True,
                                          "rollback_safe": True, "house_cleaning_controlled": True,
                                          "risk": "low"})
    assert ok is True and reasons == []


# ---- outcomes 1 + 2: skill text must REQUIRE the contracts (not silent) ----
def test_brainstorming_skill_requires_sys1_elicitation():
    t = (_REPO / "skills" / "brainstorming" / "SKILL.md").read_text(encoding="utf-8").lower()
    for needle in ["stakeholder-needs.json", "material-unknowns.json", "decision-log.md",
                   "material unknown", "before"]:
        assert needle in t, f"brainstorming SKILL.md missing SYS.1 requirement token: {needle}"

def test_writing_verification_plans_requires_md_projection():
    t = (_REPO / "skills" / "writing-verification-plans" / "SKILL.md").read_text(encoding="utf-8").lower()
    for needle in ["test-design.json", "test-design.md", "projection"]:
        assert needle in t, f"writing-verification-plans SKILL.md missing token: {needle}"
