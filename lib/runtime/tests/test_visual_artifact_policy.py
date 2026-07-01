import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "payload"))

from visual_artifact_policy import validate_visual_artifact_policy, validate_mock_iteration


# --- validate_visual_artifact_policy ---

def test_workflow_spec_no_artifact_fails():
    defects = validate_visual_artifact_policy({"spec_type": "workflow"})
    assert defects


def test_ui_spec_no_artifact_fails():
    defects = validate_visual_artifact_policy({"surfaces": ["UI"]})
    assert defects


def test_fsm_spec_with_png_passes():
    assert validate_visual_artifact_policy({
        "spec_type": "FSM",
        "surfaces": ["workflow"],
        "visual_artifacts": ["C:/some/path/diagram.png"],
    }) == []


def test_fsm_spec_with_svg_passes():
    assert validate_visual_artifact_policy({
        "spec_type": "FSM",
        "visual_artifacts": ["flow.svg"],
    }) == []


def test_fsm_spec_with_html_passes():
    assert validate_visual_artifact_policy({
        "spec_type": "FSM",
        "visual_artifacts": ["index.html"],
    }) == []


def test_fsm_spec_with_url_passes():
    assert validate_visual_artifact_policy({
        "spec_type": "FSM",
        "visual_artifacts": ["https://lil-own-prediction-gets.trycloudflare.com"],
    }) == []


def test_small_text_policy_with_na_reason_passes():
    assert validate_visual_artifact_policy({
        "spec_type": "text_policy_small",
        "small_text_only": True,
        "visual_artifact_na_reason": "Pure prose policy; no flows or UI",
    }) == []


def test_small_text_policy_without_na_reason_fails():
    defects = validate_visual_artifact_policy({
        "spec_type": "text_policy_small",
        "small_text_only": True,
    })
    assert defects
    assert any("visual_artifact_na_reason" in d for d in defects)


def test_substantial_spec_with_na_reason_passes():
    assert validate_visual_artifact_policy({
        "spec_type": "FSM",
        "visual_artifact_na_reason": "Diagram was approved separately in shared drive",
    }) == []


def test_workflow_spec_with_na_reason_passes():
    assert validate_visual_artifact_policy({
        "spec_type": "workflow",
        "visual_artifact_na_reason": "Flow diagram attached in Notion",
    }) == []


def test_data_model_spec_substantial():
    defects = validate_visual_artifact_policy({"spec_type": "data_model"})
    assert defects


# --- validate_mock_iteration ---

def test_material_change_with_improved_v2_passes():
    assert validate_mock_iteration({
        "material_final_spec_change": True,
        "mock_v1_score": 0.72,
        "mock_v2_score": 0.91,
    }) == []


def test_material_change_v2_not_greater_fails():
    defects = validate_mock_iteration({
        "material_final_spec_change": True,
        "mock_v1_score": 0.80,
        "mock_v2_score": 0.75,
    })
    assert defects
    assert any("must be greater than" in d for d in defects)


def test_material_change_missing_v2_fails():
    defects = validate_mock_iteration({
        "material_final_spec_change": True,
        "mock_v1_score": 0.70,
    })
    assert defects
    assert any("mock_v2_score is required" in d for d in defects)


def test_no_material_change_with_na_reason_passes():
    assert validate_mock_iteration({
        "material_final_spec_change": False,
        "mock_v1_score": 0.80,
        "mock_v2_na_reason": "Design unchanged; mock v1 still accurate",
    }) == []


def test_no_material_change_no_v2_no_na_reason_fails():
    defects = validate_mock_iteration({
        "material_final_spec_change": False,
        "mock_v1_score": 0.80,
    })
    assert defects


def test_no_material_change_equal_v2_passes():
    assert validate_mock_iteration({
        "material_final_spec_change": False,
        "mock_v1_score": 0.80,
        "mock_v2_score": 0.80,
    }) == []


def test_no_material_change_regressing_v2_fails():
    defects = validate_mock_iteration({
        "material_final_spec_change": False,
        "mock_v1_score": 0.80,
        "mock_v2_score": 0.60,
    })
    assert defects
    assert any("must not regress" in d for d in defects)
