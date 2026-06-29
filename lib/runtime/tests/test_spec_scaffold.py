import sys
import json
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".claude" / "lib"))
from spec_scaffold import scaffold


def test_scaffold_emits_valid_json_with_required_slots():
    reg_json, sheet = scaffold([{"cap_id": "CAP-01", "type_tags": ["editable", "persists"]}])
    caps = json.loads(reg_json)                         # MUST be valid JSON (no // comments)
    sdc = caps[0]["state_data_contract"]
    assert "reload" in sdc and "invariant" in sdc and sdc["reload"] == ""


def test_scaffold_preserves_type_tags():                # clobber-bug guard
    cap = json.loads(scaffold([{"cap_id": "CAP-01", "type_tags": ["editable", "persists"]}])[0])[0]
    assert cap["type_tags"] == ["editable", "persists"]   # not clobbered by baseline default []
    assert cap["cap_id"] == "CAP-01"


def test_prompt_sheet_carries_content_quality_prompts():
    _, sheet = scaffold([{"cap_id": "CAP-01", "type_tags": ["ui"]}])
    # content-quality items A2/A8/A9 are PROMPTS, not slots (D2)
    assert "observable" in sheet.lower() and "surface" in sheet.lower()


def test_scaffold_migration_destructive_prompts_rollback():   # reviewer falsification (§10)
    reg_json, sheet = scaffold([{"cap_id": "M", "type_tags": ["migration", "destructive"]}])
    sdc = json.loads(reg_json)[0]["state_data_contract"]
    assert {"idempotency", "rollback"} <= set(sdc) and ("undo" in sdc or "rollback" in sdc)
    assert "roll back" in sheet.lower()


def test_scaffold_baseline_slots_come_from_shared_source():   # GAP-02: scaffold side of parity
    from spec_required_fields import baseline_required_paths
    cap = json.loads(scaffold([{"cap_id": "C", "type_tags": ["ui"]}])[0])[0]

    def present(d, dotted):
        for k in dotted.split("."):
            if not isinstance(d, dict) or k not in d:
                return False
            d = d[k]
        return True

    assert all(present(cap, p) for p in baseline_required_paths())


def test_scaffold_has_no_hardcoded_baseline_literal():        # GAP-02 guard
    import inspect, spec_scaffold
    assert "_BASELINE_SLOTS" not in inspect.getsource(spec_scaffold)


def test_ui_cap_has_no_contract_slot():
    cap = json.loads(scaffold([{"cap_id": "U", "type_tags": ["ui"]}])[0])[0]
    assert cap["state_data_contract"] is None             # no applicable rule -> no slot


# ---- Task 3: end-to-end "by construction" (scaffold -> fill -> audit) ----
from spec_audit import audit_spec


def test_filled_scaffold_passes_audit_by_construction():
    reg_json, _ = scaffold([{"cap_id": "CAP-01", "type_tags": ["editable", "persists"]}])
    cap = json.loads(reg_json)[0]
    # author fills every slot with real content
    cap["user_outcome"] = "edit a note"
    cap["entry_point"] = "note.html"
    cap["entry_type"] = "ui"
    cap["reachable_path"] = "/note"
    cap["acceptance"] = {"given": "a note", "when": "user edits and saves",
                         "then": "the edited text appears on the page after reload"}
    cap["state_data_contract"]["reload"] = "reopen shows the edit"
    cap["state_data_contract"]["invariant"] = "other fields untouched"
    cap["failure_modes"] = ["empty title shows an inline error"]
    assert audit_spec([cap])["final_ready"] is True


def test_empty_scaffold_fails_audit():
    reg_json, _ = scaffold([{"cap_id": "CAP-01", "type_tags": ["editable", "persists"]}])
    cap = json.loads(reg_json)[0]   # left empty
    r = audit_spec([cap])
    assert r["final_ready"] is False
    # diagnostic: the empty acceptance trips A2 (presence drawn from the shared baseline)
    assert any(i["id"] == "A2" and i["status"] == "fail" for i in r["items"])


def test_high_risk_scaffold_presence_by_construction_but_needs_review():
    # GSG-04 honest ceiling: a filled high-risk cap passes every PRESENCE item by
    # construction, yet final_ready stays False until the independent review verdict.
    reg_json, _ = scaffold([{"cap_id": "MIG-01", "type_tags": ["migration"]}])
    cap = json.loads(reg_json)[0]
    cap["user_outcome"] = "migrate the orders table to the new schema"
    cap["entry_point"] = "migrate.py"
    cap["entry_type"] = "cli"
    cap["reachable_path"] = "migrate up"
    cap["acceptance"] = {"given": "the old schema", "when": "the migration runs",
                         "then": "stdout prints the number of rows migrated"}
    cap["state_data_contract"]["idempotency"] = "re-running is a no-op"
    cap["state_data_contract"]["rollback"] = "migrate down restores the old schema"
    cap["failure_modes"] = ["a partial migration is rolled back automatically"]
    # every per-item check passes (presence-by-construction)...
    items = audit_spec([cap])["items"]
    assert all(i["status"] == "pass" for i in items)
    # ...but high tier withholds final_ready until a review verdict (honest ceiling)
    assert audit_spec([cap])["final_ready"] is False
    assert audit_spec([cap], review_verdict="pass")["final_ready"] is True
