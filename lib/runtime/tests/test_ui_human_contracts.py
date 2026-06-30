import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "payload"))

from risk_scale import required_categories
from verify_lint import lint_test_design, lint_runtime_verdicts


UI_REQUIRED = {
    "browser-clickthrough",
    "responsive-mobile",
    "touch-targets",
    "keyboard-focus",
    "feedback-states",
    "runtime-cleanliness",
    "visual-evidence",
}


def _case(category, then=None):
    return {
        "cap_id": "UI-1",
        "category": category,
        "technique": "use-case",
        "then": then or f"{category} evidence is captured",
    }


def test_ui_entry_type_adds_ui_human_categories():
    assert UI_REQUIRED <= required_categories({"entry_type": "UI"})


def test_ui_tag_adds_ui_human_categories():
    assert UI_REQUIRED <= required_categories({"tags": ["ui", "workflow"]})


def test_ui_test_design_missing_ui_human_categories_fails():
    td = {
        "independent": True,
        "verifier": "v",
        "builder": "b",
        "skill_ui_human_available": True,
        "registry": [{"cap_id": "UI-1", "entry_type": "UI", "risk": {"entry_type": "UI"}}],
        "cases": [
            _case("happy"),
            _case("boundary"),
            _case("negative"),
            _case("error-guessing"),
        ],
    }
    blob = " ".join(lint_test_design(td))
    for category in UI_REQUIRED:
        assert category in blob


def test_ui_responsive_mobile_requires_390px_overflow_check():
    cases = [_case(c) for c in UI_REQUIRED | {"happy", "boundary", "negative", "error-guessing"}]
    for case in cases:
        if case["category"] == "responsive-mobile":
            case["then"] = "mobile layout is usable"
    td = {
        "independent": True,
        "verifier": "v",
        "builder": "b",
        "skill_ui_human_available": True,
        "registry": [{"cap_id": "UI-1", "entry_type": "UI", "risk": {"entry_type": "UI"}}],
        "cases": cases,
    }
    assert any("390px" in d and "overflow" in d for d in lint_test_design(td))


def test_ui_preflight_fails_when_skill_ui_human_unavailable():
    td = {
        "independent": True,
        "verifier": "v",
        "builder": "b",
        "skill_ui_human_available": False,
        "registry": [{"cap_id": "UI-1", "entry_type": "UI", "risk": {"entry_type": "UI"}}],
        "cases": [_case(c, "390px viewport has no horizontal overflow") for c in UI_REQUIRED | {"happy", "boundary", "negative", "error-guessing"}],
    }
    assert any("skill-ui-human" in d and "unavailable" in d for d in lint_test_design(td))


def test_ui_matches_verdict_requires_runtime_human_evidence():
    verdicts = {
        "results": [
            {
                "cap_id": "UI-1",
                "entry_type": "UI",
                "verdict": "MATCHES",
                "evidence_path": "evidence/ui-1.png",
                "evidence_url": "https://home.luminexhealthbiohack.com",
                "evidence_ts": 123,
            }
        ]
    }
    defects = lint_runtime_verdicts(verdicts)
    assert any("screenshots" in d for d in defects)
    assert any("viewport" in d for d in defects)
    assert any("touch" in d for d in defects)
    assert any("focus" in d for d in defects)
    assert any("console" in d or "page error" in d for d in defects)


def test_ui_matches_verdict_clean_with_runtime_human_evidence():
    verdicts = {
        "results": [
            {
                "cap_id": "UI-1",
                "entry_type": "UI",
                "verdict": "MATCHES",
                "evidence_path": "evidence/ui-1.png",
                "evidence_url": "https://home.luminexhealthbiohack.com",
                "evidence_ts": 123,
                "ui_human_evidence": {
                    "screenshots": ["desktop.png", "mobile-390.png"],
                    "viewport_overflow": {"desktop": False, "mobile_390": False},
                    "touch_targets": {"min_px": 44, "violations": []},
                    "keyboard_focus": {"tab_order_checked": True, "visible_focus": True},
                    "feedback_states": ["loading", "success", "error"],
                    "runtime_cleanliness": {"console_errors": [], "page_errors": []},
                },
            }
        ]
    }
    assert lint_runtime_verdicts(verdicts) == []
