import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".claude" / "lib"))
import pytest
from spec_capability_discovery import discovery_questions, build_discovery_record, unlinked_accepted


def test_discovery_sweeps_all_dimensions():
    qs = discovery_questions()
    dims = {q["dimension"] for q in qs}
    assert {"surface", "user_role", "data_mutation", "lifecycle", "failure", "deployment"} <= dims
    assert all(q.get("question") for q in qs)


def test_discovery_record_requires_reason_for_rejected_and_links_accepted():
    rec = build_discovery_record(
        answers=[{"q": "any deletes?", "a": "yes, admin can delete users"}],
        decisions=[{"cap_id": "CAP-01", "accepted": True},
                   {"cap_id": "CAP-02", "accepted": False, "reason": "out of scope v1"}],
        registry_links=[{"cap_id": "CAP-01", "registry_entry": "CAP-01"}])
    assert rec["decisions"][1]["reason"]
    assert rec["registry_links"][0]["registry_entry"] == "CAP-01"
    assert rec["candidate_cap_ids"] == ["CAP-01", "CAP-02"]
    assert len(rec["questions_asked"]) == len(discovery_questions())


def test_discovery_record_rejects_unreasoned_rejection():
    with pytest.raises(ValueError):
        build_discovery_record(answers=[], decisions=[{"cap_id": "X", "accepted": False}],
                               registry_links=[])


def test_registry_link_must_reference_accepted_cap():
    # linking a rejected (or unknown) candidate to a registry entry is an inconsistency
    with pytest.raises(ValueError):
        build_discovery_record(answers=[],
                               decisions=[{"cap_id": "X", "accepted": False, "reason": "no"}],
                               registry_links=[{"cap_id": "X", "registry_entry": "CAP-01"}])


def test_unlinked_accepted_flags_missing_links():
    # F4 completeness: an accepted candidate with no registry_link is surfaced, not lost
    rec = build_discovery_record(
        answers=[],
        decisions=[{"cap_id": "A", "accepted": True}, {"cap_id": "B", "accepted": True}],
        registry_links=[{"cap_id": "A", "registry_entry": "CAP-01"}])
    assert unlinked_accepted(rec) == ["B"]
