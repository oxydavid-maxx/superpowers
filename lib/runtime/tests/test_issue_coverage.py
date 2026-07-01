import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "payload"))

from issue_coverage import validate_issue_coverage

_RESOLVED_DIMS = {
    "answer_status": "resolved",
    "background_status": "resolved",
    "need_status": "resolved",
    "intent_status": "resolved",
    "implicit_context_status": "resolved",
}

_CLEAN_ISSUE = {
    "issue_id": "ISS-01",
    "source_turn_id": "turn-1",
    "decision_status": "resolved",
    "question_ids": ["Q-1"],
    **_RESOLVED_DIMS,
}

_CLEAN_LOG = [{"question_id": "Q-1", "answer_summary": "User wants X"}]


def test_clean_issue_passes():
    assert validate_issue_coverage([_CLEAN_ISSUE], _CLEAN_LOG) == []


def test_missing_source_turn_id_fails():
    issue = {**_CLEAN_ISSUE, "source_turn_id": ""}
    defects = validate_issue_coverage([issue], _CLEAN_LOG)
    assert any("missing source_turn_id" in d for d in defects)


def test_needs_user_dimension_blocks():
    issue = {**_CLEAN_ISSUE, "answer_status": "needs_user"}
    defects = validate_issue_coverage([issue], _CLEAN_LOG)
    assert any("answer_status" in d and "blocks Spec Draft" in d for d in defects)


def test_all_unresolved_dimensions_block():
    for dim in [
        "answer_status",
        "background_status",
        "need_status",
        "intent_status",
        "implicit_context_status",
    ]:
        issue = {**_CLEAN_ISSUE, dim: "needs_user"}
        defects = validate_issue_coverage([issue], _CLEAN_LOG)
        assert any(dim in d for d in defects), f"expected block on {dim}"


def test_resolved_without_clarification_log_entry_fails():
    issue = {**_CLEAN_ISSUE, "question_ids": ["Q-99"]}
    defects = validate_issue_coverage([issue], _CLEAN_LOG)
    assert any("Q-99" in d and "missing from clarification-log" in d for d in defects)


def test_resolved_with_matching_log_entry_passes():
    issue = {**_CLEAN_ISSUE, "question_ids": ["Q-1"]}
    assert validate_issue_coverage([issue], _CLEAN_LOG) == []


def test_deferred_with_user_approval_requires_evidence():
    issue = {
        "issue_id": "ISS-02",
        "source_turn_id": "turn-2",
        "decision_status": "deferred_with_user_approval",
        # no deferral_evidence
    }
    defects = validate_issue_coverage([issue], [])
    assert any("deferral_evidence" in d for d in defects)


def test_deferred_with_evidence_passes():
    issue = {
        "issue_id": "ISS-02",
        "source_turn_id": "turn-2",
        "decision_status": "deferred_with_user_approval",
        "deferral_evidence": "User approved deferral in turn-3",
    }
    assert validate_issue_coverage([issue], []) == []


def test_empty_coverage_passes():
    assert validate_issue_coverage([], []) == []


def test_dict_form_accepted():
    data = {"issues": [_CLEAN_ISSUE]}
    log = {"entries": _CLEAN_LOG}
    assert validate_issue_coverage(data, log) == []


def test_unrecognised_dimension_status_fails():
    issue = {**_CLEAN_ISSUE, "answer_status": "unknown_value"}
    defects = validate_issue_coverage([issue], _CLEAN_LOG)
    assert any("unrecognised status" in d for d in defects)
