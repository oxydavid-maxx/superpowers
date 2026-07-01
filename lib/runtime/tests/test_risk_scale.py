import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".claude" / "lib"))
from risk_scale import required_categories


def test_baseline():
    assert required_categories({}) == {"happy", "boundary", "negative"}


def test_high_risk_adds_integration_and_corner():
    assert {"integration", "corner"} <= required_categories({"multi_component": True})


def test_stateful_adds_state_transition():
    assert "state-transition" in required_categories({"stateful": True})


def test_deployed_adds_environment():
    assert "environment" in required_categories({"deployed": True})


def test_silent_failure_adds_targeted_case():
    assert "error-guessing" in required_categories({"silent": True})
    assert "error-guessing" not in required_categories({})


# --- non-whitelist rigor (2026-07-01 audit fix): classical ISTQB techniques alone
# proved "verified" but never exercised unknown failure space. See risk_scale docstring.

def test_high_risk_adds_exploratory_and_forbidden_state():
    reqs = required_categories({"multi_component": True})
    assert {"exploratory", "forbidden-state"} <= reqs


def test_baseline_has_no_exploratory_or_forbidden_state():
    reqs = required_categories({})
    assert "exploratory" not in reqs
    assert "forbidden-state" not in reqs


def test_user_input_adds_fuzz_and_security_abuse():
    reqs = required_categories({"user_input": True})
    assert {"fuzz", "security-abuse"} <= reqs
    assert "fuzz" not in required_categories({})
    assert "security-abuse" not in required_categories({})


def test_external_boundary_adds_fault_injection():
    reqs = required_categories({"external_boundary": True})
    assert "fault-injection" in reqs
    assert "fault-injection" not in required_categories({})


def test_ui_adds_heuristic_eval_and_assistive_tech():
    reqs = required_categories({"entry_type": "ui"})
    assert {"heuristic-eval", "assistive-tech"} <= reqs
