"""Visual artifact and mock iteration policy validators.
Pure functions; no I/O.
"""
from __future__ import annotations

SUBSTANTIAL_SPEC_TYPES = frozenset(
    ["workflow", "FSM", "UI", "multi_surface", "data_model", "orchestration", "architecture"]
)

ALLOWED_ARTIFACT_EXTENSIONS = frozenset([".png", ".svg", ".html"])


def _is_substantial(spec_meta: dict) -> bool:
    if spec_meta.get("small_text_only"):
        return False
    spec_type = spec_meta.get("spec_type", "")
    surfaces = spec_meta.get("surfaces", [])
    if spec_type in SUBSTANTIAL_SPEC_TYPES:
        return True
    if any(s in SUBSTANTIAL_SPEC_TYPES for s in surfaces):
        return True
    return False


def _has_valid_artifact(artifacts: list) -> bool:
    for a in artifacts:
        s = str(a).lower()
        if s.startswith("http://") or s.startswith("https://"):
            return True
        if any(s.endswith(ext) for ext in ALLOWED_ARTIFACT_EXTENSIONS):
            return True
    return False


def validate_visual_artifact_policy(spec_meta: dict) -> list[str]:
    """Return defect strings ([] = clean).

    spec_meta keys:
      spec_type: str
      surfaces: list[str]
      small_text_only: bool
      visual_artifacts: list[str | Path]  (URLs or file paths)
      visual_artifact_na_reason: str
    """
    if not _is_substantial(spec_meta):
        # small text-only: still require an explicit N/A reason
        if not spec_meta.get("visual_artifact_na_reason"):
            return [
                "non-substantial spec must provide visual_artifact_na_reason"
                " (set small_text_only: true and explain why no diagram is needed)"
            ]
        return []

    # substantial spec: requires a real artifact OR an explicit N/A reason
    artifacts = spec_meta.get("visual_artifacts", [])
    if _has_valid_artifact(artifacts):
        return []

    na_reason = spec_meta.get("visual_artifact_na_reason", "")
    if na_reason:
        return []

    spec_type = spec_meta.get("spec_type", "<unknown>")
    return [
        f"substantial spec (type={spec_type!r}) requires at least one visual artifact"
        " (.png/.svg/.html or URL) or an explicit visual_artifact_na_reason"
    ]


def validate_mock_iteration(mock_meta: dict) -> list[str]:
    """Return defect strings ([] = clean).

    mock_meta keys:
      material_final_spec_change: bool
      mock_v1_score: float
      mock_v2_score: float | None
      mock_v2_na_reason: str
    """
    defects: list[str] = []
    material_change = mock_meta.get("material_final_spec_change", False)

    if material_change:
        v1 = mock_meta.get("mock_v1_score")
        v2 = mock_meta.get("mock_v2_score")
        if v1 is None:
            defects.append("mock_v1_score is required when material_final_spec_change=true")
        if v2 is None:
            defects.append(
                "mock_v2_score is required when material_final_spec_change=true"
                " (or set mock_v2_na_reason if no material UI/shape change)"
            )
        elif v1 is not None and v2 <= v1:
            defects.append(
                f"mock_v2_score ({v2}) must be greater than mock_v1_score ({v1})"
                " when the final spec materially changed"
            )
    else:
        # no material change: mock v2 is optional, but if provided it must not regress
        v1 = mock_meta.get("mock_v1_score")
        v2 = mock_meta.get("mock_v2_score")
        na = mock_meta.get("mock_v2_na_reason", "")
        if v2 is None and not na:
            defects.append(
                "when material_final_spec_change=false, either supply mock_v2_score"
                " or set mock_v2_na_reason"
            )
        if v2 is not None and v1 is not None and v2 < v1:
            defects.append(
                f"mock_v2_score ({v2}) must not regress below mock_v1_score ({v1})"
            )

    return defects
