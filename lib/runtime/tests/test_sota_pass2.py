"""SOTA pass-2 verification (2026-07-01 recurrence fix): a spec may not reach FINAL
while any registry Cap-ID lacks a real prior-art/SOTA citation and has no explicit
N/A reason. Root cause this closes: an agent reused an OLD spec's SOTA references
for NEW/changed capabilities instead of actually searching for them."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".claude" / "lib"))
from sota_pass2 import validate_sota_pass2


def _reg(*cap_ids):
    return [{"cap_id": c} for c in cap_ids]


def test_missing_record_for_a_cap_fails():
    defects = validate_sota_pass2(_reg("C-1", "C-2"), [
        {"cap_id": "C-1", "sources": [{"name": "Gmail", "url": "https://x", "verdict": "adapt"}]},
    ])
    assert any("C-2" in d for d in defects)


def test_record_with_no_sources_and_no_na_reason_fails():
    defects = validate_sota_pass2(_reg("C-1"), [
        {"cap_id": "C-1", "sources": []},
    ])
    assert any("C-1" in d for d in defects)


def test_record_with_na_reason_and_no_sources_passes():
    defects = validate_sota_pass2(_reg("C-1"), [
        {"cap_id": "C-1", "sources": [], "sota_na_reason": "trivial copy-edit, no behavior change"},
    ])
    assert defects == []


def test_source_with_empty_name_or_url_does_not_count():
    defects = validate_sota_pass2(_reg("C-1"), [
        {"cap_id": "C-1", "sources": [{"name": "", "url": "", "verdict": "adopt"}]},
    ])
    assert any("C-1" in d for d in defects)


def test_reused_stale_source_flagged_when_marked_reused():
    # the exact incident: an agent reused an OLD spec's SOTA reference instead of
    # actually searching for the NEW/changed capability's prior art.
    defects = validate_sota_pass2(_reg("C-1"), [
        {"cap_id": "C-1", "sources": [{"name": "old menu", "url": "https://x", "verdict": "adopt", "reused_from_prior_spec": True}]},
    ])
    assert any("C-1" in d and "reused" in d.lower() for d in defects)


def test_fully_valid_record_passes():
    defects = validate_sota_pass2(_reg("C-1", "C-2"), [
        {"cap_id": "C-1", "sources": [{"name": "Gmail", "url": "https://gmail.com", "verdict": "adapt"}]},
        {"cap_id": "C-2", "sources": [], "sota_na_reason": "no external prior art category applies"},
    ])
    assert defects == []


def test_empty_registry_passes_vacuously():
    assert validate_sota_pass2([], []) == []
