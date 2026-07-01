"""progress_state — derive the Superpower FSM's current gate from ON-DISK GROUND TRUTH,
never from the agent's memory of the conversation (2026-07-01 fix, 光佑's design).

Root cause this closes: the Progress Line (`Superpower: now=...`) was composed by the
agent from what it remembered doing. An agent that skips S1_SOTA/S2_VERIFICATION_PLAN
could still print a plausible-looking line claiming to be further along — the line was
never CHECKED against reality. derive_current_gate() mirrors spec_audit's philosophy
(DERIVE, trust nothing self-declared): it walks the FSM stage order and returns the
EARLIEST gate whose own exit artifact is not yet present+valid on disk. A caller (a
refresh script, a hook) reads THIS file to produce the line — it is not reconstructed
from memory, so a skipped step cannot be silently claimed as done.

SCOPE (honest boundary, not silently overclaimed): S0-S3 are derived from real,
checkable artifacts (spec.md, mock-iteration.json, sota-pass2.json, stakeholder/
material-unknowns/decision-log, verify/test-design.json, docs/superpowers/plans/*.md).
S4_BUILD through S6_RELEASE are NOT YET ground-truth-derived here — once S3 is
satisfied, derive_current_gate stops at S3_IMPLEMENTATION_PLAN rather than guessing
further. Extending derivation through S4-S6 (build/verify/release evidence) is a
follow-up, not silently faked in this pass.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
from superpower_fsm import STAGES, compact_progress  # noqa: E402


def _load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def _extract_registry(spec_md):
    m = re.search(r"```registry\s*\n(.*?)\n```", spec_md or "", re.DOTALL)
    if not m:
        return []
    try:
        data = json.loads(m.group(1))
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _spec_status(spec_md):
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", spec_md or "", re.DOTALL)
    if not m:
        return ""
    sm = re.search(r"^status:\s*(.+)$", m.group(1), re.MULTILINE)
    return (sm.group(1).strip().upper() if sm else "")


def _s0_satisfied(spec_dir):
    return (spec_dir / "spec.md").is_file()


def _s1_spec_draft_satisfied(spec_dir):
    return (spec_dir / "spec.md").is_file()


def _s1_mock_v1_satisfied(spec_dir):
    meta = _load_json(spec_dir / "mock-iteration.json") or {}
    return meta.get("mock_v1_score") is not None


def _s1_sota_satisfied(spec_dir, registry):
    sys.path.insert(0, os.path.dirname(__file__))
    from sota_pass2 import validate_sota_pass2
    records = _load_json(spec_dir / "sota-pass2.json") or []
    return validate_sota_pass2(registry, records) == []


def _s1_revise_discuss_satisfied(spec_dir):
    log = spec_dir / "decision-log.md"
    return log.is_file() and bool(log.read_text(encoding="utf-8").strip())


def _s1_spec_final_satisfied(spec_dir, spec_md, registry):
    if _spec_status(spec_md) not in ("FINAL", "FINAL CANDIDATE"):
        return False
    sys.path.insert(0, os.path.dirname(__file__))
    from spec_audit import audit_spec_file
    from sys1_elicitation import validate as sys1_validate
    from visual_artifact_policy import validate_mock_iteration
    from sota_pass2 import validate_sota_pass2
    elicitation = {
        "stakeholder_needs": _load_json(spec_dir / "stakeholder-needs.json") or [],
        "material_unknowns": _load_json(spec_dir / "material-unknowns.json") or [],
        "decision_log_text": (spec_dir / "decision-log.md").read_text(encoding="utf-8")
                              if (spec_dir / "decision-log.md").is_file() else "",
        "mock_meta": _load_json(spec_dir / "mock-iteration.json") or {},
        "sota_records": _load_json(spec_dir / "sota-pass2.json") or [],
    }
    result = audit_spec_file(spec_md, tier=None, elicitation=elicitation)
    return bool(result.get("final_ready"))


def _s1_mock_v2_satisfied(spec_dir):
    sys.path.insert(0, os.path.dirname(__file__))
    from visual_artifact_policy import validate_mock_iteration
    meta = _load_json(spec_dir / "mock-iteration.json") or {}
    return validate_mock_iteration(meta) == []


def _s2_verification_plan_satisfied(root):
    verify_dir = root / ".superpowers" / "verify"
    td = _load_json(verify_dir / "test-design.json")
    if td is None:
        return False
    sys.path.insert(0, os.path.dirname(__file__))
    from verify_lint import lint_test_design
    if lint_test_design(td) != []:
        return False
    md_path = verify_dir / "test-design.md"
    if not md_path.is_file():
        return False
    from test_design_projection import parity_defects
    return parity_defects(td, md_path.read_text(encoding="utf-8")) == []


def _s3_implementation_plan_satisfied(root):
    plans_dir = root / "docs" / "superpowers" / "plans"
    if not plans_dir.is_dir():
        return False
    for f in plans_dir.glob("*.md"):
        if "## Recommended executor" in f.read_text(encoding="utf-8"):
            return True
    return False


def derive_current_gate(root):
    """Return the EARLIEST gate whose exit artifact is not yet present+valid on disk.
    root: repo root (Path). See module docstring for the S0-S3 scope boundary."""
    root = Path(root)
    spec_dir = root / ".superpowers" / "spec"
    if not _s0_satisfied(spec_dir):
        return "S0_DISCUSS"
    if not _s1_spec_draft_satisfied(spec_dir):
        return "S1_SPEC_DRAFT"
    if not _s1_mock_v1_satisfied(spec_dir):
        return "S1_EXPECTED_MOCK_V1"
    spec_md = (spec_dir / "spec.md").read_text(encoding="utf-8")
    registry = _extract_registry(spec_md)
    if not _s1_sota_satisfied(spec_dir, registry):
        return "S1_SOTA"
    if not _s1_revise_discuss_satisfied(spec_dir):
        return "S1_REVISE_DISCUSS"
    if not _s1_spec_final_satisfied(spec_dir, spec_md, registry):
        return "S1_SPEC_FINAL"
    if not _s1_mock_v2_satisfied(spec_dir):
        return "S1_EXPECTED_MOCK_V2"
    if not _s2_verification_plan_satisfied(root):
        return "S2_VERIFICATION_PLAN"
    if not _s3_implementation_plan_satisfied(root):
        return "S3_IMPLEMENTATION_PLAN"
    # S4_BUILD..S6_RELEASE: not yet ground-truth-derived (see module docstring). Report
    # the last gate this function can actually verify, rather than guessing further.
    return "S3_IMPLEMENTATION_PLAN"


def write_golden(root):
    """Write the static, canonical stage list (the 'golden' reference) — a JSON dump of
    superpower_fsm.STAGES, so it is inspectable/diffable without importing Python."""
    root = Path(root)
    fsm_dir = root / ".superpowers" / "fsm"
    fsm_dir.mkdir(parents=True, exist_ok=True)
    golden = {"schema_version": "1.0",
              "stages": [{"gate": s.gate, "skill": s.skill} for s in STAGES]}
    (fsm_dir / "golden.json").write_text(json.dumps(golden, indent=2, ensure_ascii=False), encoding="utf-8")
    return golden


def refresh_progress(root, *, owner=None, owner_by_gate=None):
    """Derive the current gate from ground truth, write BOTH golden.json and
    progress.json, and return {"current_gate", "line"}. This is what a caller (script
    or hook) runs "every time superpower is invoked" — the Progress Line comes from
    reading this file's derivation, never composed from memory."""
    root = Path(root)
    write_golden(root)
    gate = derive_current_gate(root)
    stage = next(s for s in STAGES if s.gate == gate)
    line = compact_progress(gate, stage.skill, owner=owner, owner_by_gate=owner_by_gate)
    fsm_dir = root / ".superpowers" / "fsm"
    fsm_dir.mkdir(parents=True, exist_ok=True)
    progress = {
        "schema_version": "1.0",
        "current_gate": gate,
        "derived_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
        "line": line,
    }
    (fsm_dir / "progress.json").write_text(json.dumps(progress, indent=2, ensure_ascii=False), encoding="utf-8")
    return progress
