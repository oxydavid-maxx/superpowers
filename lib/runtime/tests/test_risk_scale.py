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
