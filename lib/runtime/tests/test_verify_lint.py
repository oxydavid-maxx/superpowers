import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".claude" / "lib"))
from verify_lint import (lint_technique, lint_proxy, lint_round_trip, lint_pairwise,
                         lint_error_guessing, lint_ui_evidence, lint_independence, lint_all,
                         lint_test_design)


def test_lint_test_design_flags_missing_category():
    td = {"independent": True, "verifier": "v", "builder": "b",
          "registry": [{"cap_id": "C", "risk": {"multi_component": True}}],
          "cases": [{"cap_id": "C", "category": "happy", "technique": "use-case",
                     "then": "the user sees the dashboard with their note"}]}
    blob = " ".join(lint_test_design(td))
    assert "integration" in blob


def test_lint_test_design_flags_missing_registry():    # reviewer fix: cases-but-no-registry slip-through
    td = {"independent": True, "verifier": "v", "builder": "b",
          "cases": [{"cap_id": "C", "category": "happy", "technique": "use-case", "then": "user sees X"}]}
    assert any("no registry" in d for d in lint_test_design(td))


def test_lint_test_design_clean_when_complete():
    td = {"independent": True, "verifier": "v", "builder": "b",
          "registry": [{"cap_id": "C", "risk": {}}],
          "cases": [
            {"cap_id": "C", "category": "happy", "technique": "use-case", "then": "user sees X"},
            {"cap_id": "C", "category": "boundary", "technique": "BVA", "then": "empty shows placeholder to user"},
            {"cap_id": "C", "category": "negative", "technique": "EP", "then": "bad input shows error to user"},
            {"cap_id": "C", "category": "error-guessing", "technique": "error-guessing", "then": "double-submit shows one entry to user"}]}
    assert lint_test_design(td) == []


# TD-02 technique present
def test_missing_technique_fails():
    assert lint_technique({"cap_id": "C", "category": "boundary", "then": "x"}) != []

def test_invalid_technique_fails():
    assert lint_technique({"cap_id": "C", "technique": "vibes", "then": "x"}) != []

def test_valid_technique_clean():
    assert lint_technique({"cap_id": "C", "technique": "BVA", "then": "x appears"}) == []


# TD-03 proxy assertion
def test_http_200_is_proxy():
    assert lint_proxy({"cap_id": "C", "then": "HTTP 200 returned"}) != []

def test_looks_ok_is_proxy():
    assert lint_proxy({"cap_id": "C", "then": "editor looks big"}) != []

def test_unverified_is_proxy():
    assert lint_proxy({"cap_id": "C", "then": "UNVERIFIED pending browser"}) != []

def test_real_observable_clean():
    assert lint_proxy({"cap_id": "C", "then": "card with 'X' appears in #curator-panel"}) == []

def test_empty_assertion_flagged():
    assert lint_proxy({"cap_id": "C", "then": ""}) != []


# TD-04 round-trip
def test_persist_without_reload_flagged():
    cap = {"cap_id": "C", "risk": {"persists": True}}
    assert lint_round_trip(cap, [{"cap_id": "C", "then": "file saved"}]) != []

def test_persist_with_reload_clean():
    cap = {"cap_id": "C", "risk": {"persists": True}}
    cases = [{"cap_id": "C", "then": "after reload, body changed and frontmatter untouched"}]
    assert lint_round_trip(cap, cases) == []

def test_nonpersist_not_required():
    assert lint_round_trip({"cap_id": "C", "risk": {}}, [{"cap_id": "C", "then": "x"}]) == []


# TD-09 pairwise
def test_three_inputs_without_pairwise_flagged():
    assert lint_pairwise({"cap_id": "C", "risk": {"inputs": 3}}, [{"cap_id": "C", "technique": "BVA"}]) != []

def test_three_inputs_with_pairwise_clean():
    assert lint_pairwise({"cap_id": "C", "risk": {"inputs": 3}}, [{"cap_id": "C", "technique": "pairwise"}]) == []

def test_two_inputs_not_required():
    assert lint_pairwise({"cap_id": "C", "risk": {"inputs": 2}}, []) == []


# TD-10 error-guessing
def test_all_confirmatory_flagged():
    assert lint_error_guessing("C", [{"cap_id": "C", "category": "happy"}]) != []

def test_has_error_guessing_clean():
    assert lint_error_guessing("C", [{"cap_id": "C", "category": "error-guessing"}]) == []


# TD-05 UI deployed-surface evidence
def test_ui_no_evidence_blocks():
    assert lint_ui_evidence({"cap_id": "C", "entry_type": "UI", "verdict": "MATCHES", "evidence_path": ""}) != []

def test_ui_localhost_evidence_blocks():
    c = {"cap_id": "C", "entry_type": "UI", "verdict": "MATCHES", "evidence_path": "s.png", "evidence_url": "http://localhost:8799/x"}
    assert lint_ui_evidence(c) != []

def test_ui_deployed_evidence_clean():
    c = {"cap_id": "C", "entry_type": "UI", "verdict": "MATCHES", "evidence_path": "s.png", "evidence_url": "https://home.luminexhealthbiohack.com/x"}
    assert lint_ui_evidence(c) == []

def test_non_ui_not_required():
    assert lint_ui_evidence({"cap_id": "C", "entry_type": "CLI", "verdict": "MATCHES"}) == []


# TD-07 independence
def test_missing_independence_flagged():
    assert lint_independence({"verifier": "x"}) != []

def test_verifier_equals_builder_flagged():
    assert lint_independence({"independent": True, "verifier": "a", "builder": "a"}) != []

def test_independent_distinct_clean():
    assert lint_independence({"independent": True, "verifier": "v", "builder": "b"}) == []


# Task 11 aggregator
def test_lint_all_collects_specific_defects():
    td = {"independent": True, "verifier": "v", "builder": "b",
          "registry": [{"cap_id": "C", "risk": {"persists": True, "inputs": 3}}],
          "cases": [{"cap_id": "C", "category": "happy", "technique": "use-case", "then": "HTTP 200"}]}
    blob = " ".join(lint_all(td))
    assert "proxy assertion" in blob     # then=HTTP 200
    assert "round-trip" in blob          # persists, no reload
    assert "pairwise" in blob            # 3 inputs, no pairwise case
    assert "error-guessing" in blob      # no fault-targeting case


def test_round_trip_reload_without_invariant_flagged():    # asymmetric (reviewer fix)
    cap = {"cap_id": "C", "risk": {"persists": True}}
    assert lint_round_trip(cap, [{"cap_id": "C", "then": "after reload the body changed"}]) != []

def test_lint_all_clean_design_empty():
    td = {"independent": True, "verifier": "v", "builder": "b",
          "registry": [{"cap_id": "C", "risk": {}}],
          "cases": [{"cap_id": "C", "category": "error-guessing", "technique": "error-guessing",
                     "then": "bad input shows an inline error message to the user"}]}
    assert lint_all(td) == []
