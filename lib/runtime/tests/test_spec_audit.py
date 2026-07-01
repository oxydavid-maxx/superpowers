import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".claude" / "lib"))
from spec_audit import audit_spec, derive_risk_tier

AUTHZ_CAP = [{"cap_id": "CAP-01", "type_tags": ["authz", "money"],
              "user_outcome": "transfer funds", "entry_point": "pay.html", "entry_type": "ui",
              "reachable_path": "/pay", "acceptance": {"given": "a balance", "when": "user transfers",
              "then": "the recipient balance increases by the amount, visible on the page after reload"},
              "state_data_contract": {"reload": "balance persists", "invariant": "no double-spend"},
              "failure_modes": ["insufficient funds shows an inline error"], "gap_questions": []}]

def test_derive_high_from_risk_tags():
    assert derive_risk_tier(AUTHZ_CAP) == "high"

def test_supplied_trivial_cannot_downgrade_authz():   # THE §15.0 falsification
    r = audit_spec(AUTHZ_CAP, tier="trivial")
    assert r["risk_tier"] == "high"
    assert r["final_ready"] is False                   # high tier needs review verdict, absent here

def test_empty_registry_is_defect_not_vacuous():       # P0-1 / I-1
    r = audit_spec([])
    assert r["final_ready"] is False and "error" in r

def test_explicit_trivial_no_capability_passes():
    r = audit_spec([], intent="trivial-no-capability")
    assert r["risk_tier"] == "trivial" and r["final_ready"] is True

THIN_EDIT = [{"cap_id": "CAP-01", "type_tags": ["editable", "persists"],
              "user_outcome": "edit a task", "entry_point": "task.html", "entry_type": "ui",
              "reachable_path": "/task/1", "acceptance": {"given": "a task", "when": "user edits", "then": "saved"},
              "state_data_contract": None, "failure_modes": [], "gap_questions": []}]


def test_thin_edit_spec_cannot_final():           # THE falsification
    r = audit_spec(THIN_EDIT, tier="standard")
    assert r["final_ready"] is False
    a4 = [i for i in r["items"] if i["id"] == "A4" and i["cap_id"] == "CAP-01"][0]
    assert a4["status"] == "fail"


def _full_elicitation_for(cap_id):
    return {
        "stakeholder_needs": [{"need_id": "N-1"}],
        "material_unknowns": [{"id": "U-1", "status": "resolved"}],
        "decision_log_text": "decided X because Y",
        "mock_meta": {"material_final_spec_change": False, "mock_v2_na_reason": "no material change"},
        "sota_records": [{"cap_id": cap_id, "sources": [{"name": "Gmail", "url": "https://gmail.com", "verdict": "adapt"}]}],
    }


def test_complete_edit_spec_can_final():           # control
    cap = dict(THIN_EDIT[0])
    cap["state_data_contract"] = {"reload": "reopen shows the edit", "invariant": "frontmatter untouched"}
    cap["failure_modes"] = ["empty title shows inline error"]
    cap["acceptance"] = {"given": "a task", "when": "user edits body and saves",
                         "then": "the edited body is visible to the user after reload"}
    cap["need_ids"] = ["N-1"]
    r = audit_spec([cap], tier="standard", elicitation=_full_elicitation_for("CAP-01"))
    assert r["final_ready"] is True



# ---- Task 2: canonical risk_tier key + schema parity ----
import json, jsonschema
from pathlib import Path as _Path
SCHEMA = json.loads((_Path.home()/".claude"/"lib"/"spec_audit.schema.json").read_text(encoding="utf-8"))

def test_output_key_is_risk_tier_not_tier():
    r = audit_spec(AUTHZ_CAP, tier="high", review_verdict="pass")
    assert "risk_tier" in r and "tier" not in r

def test_output_validates_against_schema():
    cap = dict(AUTHZ_CAP[0]); cap["need_ids"] = ["N-1"]
    jsonschema.validate(audit_spec([cap], tier="high", review_verdict="pass",
                                    elicitation=_full_elicitation_for("CAP-01")), SCHEMA)



# ---- Task 3: A4 tag-complete + anti-divergence guard ----
from spec_audit import a4_state_data_contract

def test_a4_destructive_needs_undo_or_rollback():
    cap = {"type_tags": ["destructive"], "state_data_contract": {"reload": "x", "invariant": "y"}}
    assert a4_state_data_contract(cap) == "fail"
    cap["state_data_contract"]["rollback"] = "restore from snapshot"
    assert a4_state_data_contract(cap) == "pass"

def test_a4_migration_and_schema_change_need_idempotency_and_rollback():
    for tag in ("migration", "schema_change"):
        cap = {"type_tags": [tag], "state_data_contract": {"rollback": "down"}}
        assert a4_state_data_contract(cap) == "fail"
        cap["state_data_contract"]["idempotency"] = "re-run is a no-op"
        assert a4_state_data_contract(cap) == "pass"

def test_a4_data_loss_needs_undo_or_rollback():
    assert a4_state_data_contract({"type_tags": ["data_loss"], "state_data_contract": {}}) == "fail"

def test_a4_concurrent_needs_invariant():
    assert a4_state_data_contract({"type_tags": ["concurrent"], "state_data_contract": {}}) == "fail"
    assert a4_state_data_contract({"type_tags": ["concurrent"], "state_data_contract": {"invariant": "serialized writes"}}) == "pass"

def test_a4_non_risk_cap_passes():
    assert a4_state_data_contract({"type_tags": ["ui"]}) == "pass"

def test_no_highrisk_tag_escapes_a4():
    # GAP-01/GAP-02: high-risk tags are DERIVED from RULES; every one must be matched by a
    # rule (so A4 demands a contract for it). No inline _HIGH_RISK_TAGS / _A4_TAGS literals.
    from spec_required_fields import high_risk_tags, applicable_rules
    assert all(applicable_rules([t]) for t in high_risk_tags())



# ---- Task 4: A8 surface↔acceptance consistency ----
from spec_audit import a8_surface_consistency

def test_a8_ui_cap_with_cli_acceptance_fails():
    cap = {"type_tags": ["ui"], "entry_type": "ui",
           "acceptance": {"given": "a shell", "when": "I run `transfer --to X`", "then": "stdout prints the new balance"}}
    assert a8_surface_consistency(cap) == "fail"

def test_a8_ui_cap_with_visible_acceptance_passes():
    cap = {"type_tags": ["ui"], "entry_type": "ui",
           "acceptance": {"given": "the page", "when": "user clicks Save", "then": "a success banner appears on screen"}}
    assert a8_surface_consistency(cap) == "pass"

def test_a8_cli_cap_with_visible_acceptance_fails():
    cap = {"type_tags": ["cli_contract"], "entry_type": "cli",
           "acceptance": {"given": "x", "when": "y", "then": "a banner appears on the page"}}
    assert a8_surface_consistency(cap) == "fail"

def test_a8_unscored_surface_passes():
    cap = {"type_tags": ["library_api"], "entry_type": "library",
           "acceptance": {"given": "x", "when": "y", "then": "the returned object has field z"}}
    assert a8_surface_consistency(cap) == "pass"



# ---- Task 5: intent:trivial-no-capability via .md + required reason ----
from spec_audit import audit_spec_file

def test_intent_trivial_via_md_with_reason_passes():
    md = "---\nintent: trivial-no-capability\nreason: pure docs change, no runtime behaviour\n---\n# Spec\n"
    assert audit_spec_file(md)["final_ready"] is True

def test_intent_trivial_via_md_without_reason_fails():
    md = "---\nintent: trivial-no-capability\n---\n# Spec\n"   # no reason
    r = audit_spec_file(md)
    assert r["final_ready"] is False and "reason" in (r.get("error") or "").lower()

def test_no_registry_no_intent_still_fails():
    assert audit_spec_file("# Spec\njust prose\n")["final_ready"] is False



# ---- Task 6: CLI emits spec_sha record ----
import subprocess, hashlib as _hashlib

def test_cli_emits_spec_sha(tmp_path):
    import sys as _sys, json as _json
    AUDIT = _Path.home()/".claude"/"lib"/"spec_audit.py"
    md = tmp_path/"spec.md"
    md.write_text("---\nintent: trivial-no-capability\nreason: docs only\n---\n# Spec\n", encoding="utf-8")
    out = subprocess.run([_sys.executable, str(AUDIT), str(md)], capture_output=True, text=True)
    rec = _json.loads(out.stdout)
    assert rec["spec_sha"] == _hashlib.sha256(md.read_text(encoding="utf-8").encode("utf-8")).hexdigest()
    assert rec["spec_path"] == str(md)


# Task 2: A2 oracle_complete
from spec_audit import a2_oracle_complete

def test_missing_then_fails():
    assert a2_oracle_complete({"acceptance": {"given": "x", "when": "y", "then": ""}}) == "fail"

def test_proxy_then_fails():
    assert a2_oracle_complete({"acceptance": {"given": "x", "when": "y", "then": "HTTP 200"}}) == "fail"

def test_observable_then_passes():
    assert a2_oracle_complete({"acceptance": {"given": "x", "when": "y", "then": "a card appears in #panel"}}) == "pass"


# Task 3: A3 surface + A6 type_tags
from spec_audit import a3_surface_complete, a6_type_tags_required

def test_a3_missing_path_fails():
    assert a3_surface_complete({"entry_point": "x", "entry_type": "ui", "reachable_path": ""}) == "fail"

def test_a3_complete_passes():
    assert a3_surface_complete({"entry_point": "x", "entry_type": "ui", "reachable_path": "/x"}) == "pass"

def test_a6_no_tags_fails():
    assert a6_type_tags_required({"type_tags": []}) == "fail"

def test_a6_unknown_tag_fails():
    assert a6_type_tags_required({"type_tags": ["bogus"]}) == "fail"

def test_a6_known_tag_passes():
    assert a6_type_tags_required({"type_tags": ["editable"]}) == "pass"


# Task 4: A5 failure_modes + A7 gap_questions
from spec_audit import a5_failure_modes, a7_gap_questions_resolved

def test_a5_no_modes_fails():
    assert a5_failure_modes({"failure_modes": []}) == "fail"

def test_a5_has_mode_passes():
    assert a5_failure_modes({"failure_modes": ["empty input shows error"]}) == "pass"

def test_a7_open_question_fails():
    assert a7_gap_questions_resolved({"gap_questions": ["what is the size limit?"]}) == "fail"

def test_a7_no_open_questions_passes():
    assert a7_gap_questions_resolved({"gap_questions": []}) == "pass"


# Task 5: risk-scaling + NON-Web falsification
def test_trivial_tier_cannot_downgrade_standard_registry():
    # Under §15.0, tier="trivial" cannot be forced on a non-empty registry;
    # derive_risk_tier returns "standard" for cli_contract caps, and supplied "trivial"
    # cannot downgrade — the result stays "standard". final_ready is False due to A5 fail.
    cap = {"cap_id": "C", "type_tags": ["cli_contract"],
           "acceptance": {"given": "a", "when": "b", "then": "the user sees output X"},
           "entry_point": "cli", "entry_type": "cli", "reachable_path": "--run",
           "failure_modes": [], "gap_questions": [], "state_data_contract": None}
    r = audit_spec([cap], tier="trivial")
    assert r["risk_tier"] == "standard"   # trivial cannot downgrade standard
    assert r["final_ready"] is False      # A5 fails (no failure modes)


def test_non_web_migration_missing_rollback_fails():   # NON-Web falsification
    cap = {"cap_id": "MIG-01", "type_tags": ["migration", "schema_change", "destructive"],
           "user_outcome": "migrate the DB", "entry_point": "migrate.py", "entry_type": "cli",
           "reachable_path": "migrate up",
           "acceptance": {"given": "old schema", "when": "migrate up", "then": "new schema, rows preserved, visible in a query"},
           "state_data_contract": None, "failure_modes": [], "gap_questions": []}
    assert audit_spec([cap], tier="standard")["final_ready"] is False


_HIGH_CAP = {"cap_id": "A", "type_tags": ["authz"], "acceptance": {"given": "a", "when": "b", "then": "user sees their dashboard"},
             "entry_point": "x", "entry_type": "api", "reachable_path": "/x",
             "failure_modes": ["denied request shows a 403 page to the user"], "gap_questions": [],
             "state_data_contract": {"invariant": "only the owner can access their data"}}


def test_high_tier_flags_independent_review():
    r = audit_spec([_HIGH_CAP], tier="high")
    assert r["independent_review"]["required"] is True
    assert r["final_ready"] is False                      # not yet reviewed


def test_high_tier_unblocks_when_review_passes():          # reviewer fix: the unblock path
    cap = dict(_HIGH_CAP); cap["need_ids"] = ["N-1"]
    r = audit_spec([cap], tier="high", review_verdict="pass", elicitation=_full_elicitation_for("A"))
    assert r["final_ready"] is True
    assert r["independent_review"]["verdict"] == "pass"


def test_a5_junk_token_fails():                            # reviewer fix: ['ok'] was gameable
    assert a5_failure_modes({"failure_modes": ["ok"]}) == "fail"


def test_a3_tbd_path_fails():                              # reviewer fix: 'TBD' was passing
    assert a3_surface_complete({"entry_point": "x", "entry_type": "ui", "reachable_path": "TBD"}) == "fail"


# --- round-5 review fixes: A8 dead-branch, A9 tag↔prose, intent anchor ---
from spec_audit import a8_surface_consistency, a9_tag_prose_consistency, audit_spec_file


def test_a8_ui_cap_cli_only_outcome_fails():           # Imp-1: dead-branch removed
    cap = {"entry_type": "ui", "acceptance": {"then": "stdout prints the result, exit code 0"}}
    assert a8_surface_consistency(cap) == "fail"

def test_a8_ui_cap_visible_outcome_passes():
    cap = {"entry_type": "ui", "acceptance": {"then": "a success banner appears on the page"}}
    assert a8_surface_consistency(cap) == "pass"

def test_a9_money_prose_without_tag_fails():            # Imp-2: under-tagged high-risk cap
    cap = {"type_tags": ["ui"], "acceptance": {"when": "user transfers money",
           "then": "a banner appears showing the new balance"}}
    assert a9_tag_prose_consistency(cap) == "fail"

def test_a9_money_prose_with_tag_passes():
    cap = {"type_tags": ["ui", "money"], "acceptance": {"then": "the new balance is shown"}}
    assert a9_tag_prose_consistency(cap) == "pass"

def test_a9_destructive_prose_without_tag_fails():
    cap = {"type_tags": ["ui"], "acceptance": {"then": "the record is permanently deleted"}}
    assert a9_tag_prose_consistency(cap) == "fail"

def test_a9_under_tagged_money_cap_cannot_final():      # end-to-end: derives standard, A9 blocks
    cap = {"cap_id": "X", "type_tags": ["ui"], "entry_point": "p.html", "entry_type": "ui",
           "reachable_path": "/p", "acceptance": {"given": "a", "when": "user pays",
           "then": "a banner appears showing the new balance on the page"},
           "state_data_contract": None, "failure_modes": ["card declined shows an error"], "gap_questions": []}
    r = audit_spec([cap])
    assert r["risk_tier"] == "standard" and r["final_ready"] is False

def test_intent_trailing_garbage_rejected():           # Minor: anchored intent regex
    md = "---\nintent: trivial-no-capability evil\nreason: docs\n---\n# Spec\n"
    assert audit_spec_file(md)["final_ready"] is False


# --- A10: elicitation/mock/SOTA artifact presence (2026-07-01 recurrence-fix audit) ---
# Real incident: two specs went straight to "FINAL CANDIDATE" with no DRAFT step, no
# stakeholder-needs.json, no mock v1/v2, and reused an OLD spec's SOTA references for
# 3 new/changed capabilities instead of actually searching prior art. Progress-line
# format checks never catch this — only checking the artifacts themselves does.

_STANDARD_CAP = [{"cap_id": "C-1", "type_tags": ["ui"], "entry_point": "p.html",
                  "entry_type": "ui", "reachable_path": "/p", "need_ids": ["N-1"],
                  "acceptance": {"given": "a", "when": "b", "then": "a banner appears on the page"},
                  "state_data_contract": None, "failure_modes": ["a clear error appears"],
                  "gap_questions": []}]

_VALID_ELICITATION = {
    "stakeholder_needs": [{"need_id": "N-1"}],
    "material_unknowns": [{"id": "U-1", "status": "resolved"}],
    "decision_log_text": "decided X because Y",
    "mock_meta": {"material_final_spec_change": False, "mock_v2_na_reason": "no material change"},
    "sota_records": [{"cap_id": "C-1", "sources": [{"name": "Gmail", "url": "https://gmail.com", "verdict": "adapt"}]}],
}


def test_a10_missing_all_elicitation_artifacts_blocks_final():
    r = audit_spec(_STANDARD_CAP, tier="standard")     # no elicitation supplied at all
    a10 = next(i for i in r["items"] if i["id"] == "A10")
    assert a10["status"] == "fail"
    assert r["final_ready"] is False


def test_a10_reused_sota_source_blocks_final():        # the exact incident: reused old spec's SOTA
    elicitation = dict(_VALID_ELICITATION)
    elicitation["sota_records"] = [{"cap_id": "C-1", "sources": [
        {"name": "old menu", "url": "https://x", "verdict": "adopt", "reused_from_prior_spec": True}]}]
    r = audit_spec(_STANDARD_CAP, tier="standard", elicitation=elicitation)
    a10 = next(i for i in r["items"] if i["id"] == "A10")
    assert a10["status"] == "fail" and "reused" in a10["detail"].lower()
    assert r["final_ready"] is False


def test_a10_missing_mock_v2_when_spec_materially_changed_blocks_final():
    elicitation = dict(_VALID_ELICITATION)
    elicitation["mock_meta"] = {"material_final_spec_change": True, "mock_v1_score": 0.6}  # no mock_v2_score
    r = audit_spec(_STANDARD_CAP, tier="standard", elicitation=elicitation)
    a10 = next(i for i in r["items"] if i["id"] == "A10")
    assert a10["status"] == "fail"
    assert r["final_ready"] is False


def test_a10_complete_elicitation_passes_and_allows_final():
    r = audit_spec(_STANDARD_CAP, tier="standard", elicitation=_VALID_ELICITATION)
    a10 = next(i for i in r["items"] if i["id"] == "A10")
    assert a10["status"] == "pass"
    assert r["final_ready"] is True


def test_a10_exempt_for_trivial_tier():
    r = audit_spec([], tier="trivial", intent="trivial-no-capability")
    assert not any(i["id"] == "A10" for i in r["items"])


def test_audit_spec_file_forwards_elicitation_to_allow_final():
    md = """# Spec

```registry
[{"cap_id": "C-1", "type_tags": ["ui"], "entry_point": "p.html", "entry_type": "ui",
  "reachable_path": "/p", "need_ids": ["N-1"],
  "acceptance": {"given": "a", "when": "b", "then": "a banner appears on the page"},
  "state_data_contract": null, "failure_modes": ["a clear error appears"], "gap_questions": []}]
```
"""
    r = audit_spec_file(md, tier="standard", elicitation=_full_elicitation_for("C-1"))
    assert r["final_ready"] is True


def test_audit_spec_file_without_elicitation_blocks_standard_tier():
    md = """# Spec

```registry
[{"cap_id": "C-1", "type_tags": ["ui"], "entry_point": "p.html", "entry_type": "ui",
  "reachable_path": "/p",
  "acceptance": {"given": "a", "when": "b", "then": "a banner appears on the page"},
  "state_data_contract": null, "failure_modes": ["a clear error appears"], "gap_questions": []}]
```
"""
    r = audit_spec_file(md, tier="standard")
    assert r["final_ready"] is False
