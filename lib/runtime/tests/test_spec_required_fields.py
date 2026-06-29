import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".claude" / "lib"))
from spec_required_fields import applicable_rules, required_contract_fields
from spec_audit import a4_state_data_contract


def test_map_requires_invariant_for_authz():
    assert "invariant" in required_contract_fields(["authz"])


def test_migration_requires_idempotency_and_rollback():
    req = required_contract_fields(["migration"])
    assert {"idempotency", "rollback"} <= req


def test_parity_audit_consumes_map():
    # A cap missing a map-required field MUST fail A4; supplying exactly the
    # map's required fields MUST pass. This couples the audit to the map.
    for tags in (["authz"], ["migration"], ["destructive"], ["stateful"]):
        req = required_contract_fields(tags)
        empty = {"type_tags": tags, "state_data_contract": {}}
        assert a4_state_data_contract(empty) == "fail"
        filled = {"type_tags": tags, "state_data_contract": {f: "x" for f in req}}
        assert a4_state_data_contract(filled) == "pass"


def test_parity_new_rule_propagates(monkeypatch):
    import spec_required_fields as srf
    extra = {"id": "x", "when_any": ["cache_sensitive"], "requires": ["invalidation"], "prompt": "?"}
    monkeypatch.setattr(srf, "RULES", srf.RULES + [extra])
    assert "invalidation" in srf.required_contract_fields(["cache_sensitive"])


def test_high_risk_tags_derived_from_rules():        # GAP-01
    from spec_required_fields import high_risk_tags
    assert {"authz", "money", "migration", "destructive", "data_loss",
            "schema_change", "concurrent"} == high_risk_tags()
    assert "editable" not in high_risk_tags()


def test_adding_high_risk_rule_changes_derivation(monkeypatch):   # GAP-01 falsification
    import spec_required_fields as srf
    from spec_audit import derive_risk_tier
    cap = {"cap_id": "C", "type_tags": ["cache_sensitive"]}
    assert derive_risk_tier([cap]) == "standard"
    monkeypatch.setattr(srf, "RULES", srf.RULES + [
        {"id": "cache-high", "when_any": ["cache_sensitive"], "requires": ["invalidation"],
         "risk_tier": "high", "prompt": "?"}])
    assert derive_risk_tier([cap]) == "high"          # derivation reclassifies — no second truth


def test_no_inline_high_risk_literal_in_audit():      # GAP-01 guard
    import inspect, spec_audit
    assert "_HIGH_RISK_TAGS = {" not in inspect.getsource(spec_audit)


def test_baseline_audit_scaffold_parity(monkeypatch):   # GAP-02 falsification
    import spec_required_fields as srf
    from spec_audit import baseline_presence_ok
    monkeypatch.setattr(srf, "BASELINE_FIELDS", srf.BASELINE_FIELDS + [
        {"path": "owner", "default": "", "kind": "required", "audit_item": "A3", "prompt": "Owner?"}])
    assert "owner" in srf.baseline_required_paths()
    assert "owner" in srf.baseline_slot_skeleton()
    assert baseline_presence_ok({"owner": ""}) is False
