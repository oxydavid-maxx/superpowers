import re
from pathlib import Path

SKILL = Path(__file__).resolve().parents[3] / "skills" / "writing-verification-plans" / "SKILL.md"


def _text():
    return SKILL.read_text(encoding="utf-8")


def test_methodology_marker_present_with_iso_date():
    m = re.search(r"methodology-sota-reviewed:\s*(\d{4}-\d{2}-\d{2})", _text())
    assert m, "SKILL.md must carry a `methodology-sota-reviewed: YYYY-MM-DD` marker"


def test_two_pass_sota_substep_heading_present():
    assert "## Two-Pass SOTA (verification methodology)" in _text()


def test_triad_requirements_present():
    t = _text().lower()
    for word in ("property-based", "mutation", "branch coverage", "verification-sota-verdicts"):
        assert word in t, f"SKILL.md must require the triad element: {word!r}"
