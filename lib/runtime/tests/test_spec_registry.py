import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".claude" / "lib"))
from spec_registry import extract_registry, a1_capability_complete
from spec_audit import audit_spec_file

_THIN_MD = """# Spec
We expose CAP-01 (edit a task).

```registry
[{"cap_id":"CAP-01","type_tags":["editable","persists"],"user_outcome":"edit a task",
  "entry_point":"t","entry_type":"ui","reachable_path":"/t",
  "acceptance":{"given":"a task","when":"user edits","then":"saved"},
  "state_data_contract":null,"failure_modes":[],"gap_questions":[]}]
```
"""

_PROSE_DROPS_CAP = """# Spec
We expose CAP-01 and CAP-02 (the AI panel).

```registry
[{"cap_id":"CAP-01","type_tags":["ui"],"entry_point":"t","entry_type":"ui","reachable_path":"/t",
  "acceptance":{"given":"a","when":"b","then":"user sees the list"},"failure_modes":["bad input shows an error to the user"],"gap_questions":[],"state_data_contract":null}]
```
"""


def test_extract_registry_reads_block():
    reg = extract_registry(_THIN_MD)
    assert len(reg) == 1 and reg[0]["cap_id"] == "CAP-01"


def test_extract_registry_empty_when_no_block():
    assert extract_registry("# spec with no registry block") == []


def test_a1_flags_prose_cap_missing_from_registry():
    reg = extract_registry(_PROSE_DROPS_CAP)
    missing = a1_capability_complete(_PROSE_DROPS_CAP, reg)
    assert "CAP-02" in missing and "CAP-01" not in missing


def test_audit_spec_file_thin_edit_cannot_final():        # END-TO-END falsification (.md → audit)
    r = audit_spec_file(_THIN_MD, tier="standard")
    assert r["final_ready"] is False
    a4 = [i for i in r["items"] if i["id"] == "A4"][0]
    assert a4["status"] == "fail"


def test_audit_spec_file_dropped_cap_fails_a1():
    r = audit_spec_file(_PROSE_DROPS_CAP, tier="standard")
    a1 = [i for i in r["items"] if i["id"] == "A1"][0]
    assert a1["status"] == "fail"
